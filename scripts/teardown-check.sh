#!/usr/bin/env bash
# teardown-check.sh: list any billable AWS resources from this project that are still alive.
# Strictly READ-ONLY: it only runs list/describe commands and never creates or deletes anything.
#
# Usage: ./scripts/teardown-check.sh        (region defaults to ap-south-1; override with AWS_REGION=...)
# Exit code: 0 = ALL CLEAR, 1 = leftovers found (or something couldn't be checked).
# Run it after every `terraform destroy` (RUNBOOK Part D).

set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
FOUND=0

# Make sure we're logged in to AWS at all. Otherwise every check would "find nothing" and wrongly say ALL CLEAR.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS CLI is not authenticated (try: export AWS_PROFILE=devops-lab)." >&2
  exit 1
fi
echo "Checking region $REGION in account $(aws sts get-caller-identity --query Account --output text)..."
echo

# check "<label>" <aws command...>
# Runs a read-only AWS command that prints resource names/IDs as text.
# Empty output means none exist. Any output, or a failed command, counts as a leftover.
check() {
  local label="$1"; shift
  local out
  if ! out="$("$@" 2>&1)"; then
    printf '  %-46s ⚠ could not check: %s\n' "$label" "$(echo "$out" | head -1)"
    FOUND=1
    return
  fi
  # The CLI's text output can print "None" for empty results. Strip it, along with whitespace.
  out="$(echo "$out" | tr '\t' '\n' | grep -v -x -e 'None' -e '' || true)"
  if [ -n "$out" ]; then
    printf '  %-46s ⚠ FOUND:\n' "$label"
    echo "$out" | sed 's/^/      - /'
    FOUND=1
  else
    printf '  %-46s ok (none)\n' "$label"
  fi
}

# The control plane bills $0.10/hour on its own.
check "EKS clusters" \
  aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text
# Worker nodes are EC2 instances. "stopped" instances still pay for their disks.
check "EC2 instances (not terminated)" \
  aws ec2 describe-instances --region "$REGION" \
    --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].InstanceId' --output text
# We never create these, but a manual experiment might have. They're expensive.
check "NAT gateways" \
  aws ec2 describe-nat-gateways --region "$REGION" \
    --filter Name=state,Values=pending,available \
    --query 'NatGateways[].NatGatewayId' --output text
# A Service of type LoadBalancer would create one of these behind Terraform's back.
check "Load balancers (ALB/NLB)" \
  aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text
check "Load balancers (classic)" \
  aws elb describe-load-balancers --region "$REGION" --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text
# Elastic IPs are billed hourly.
check "Elastic IPs" \
  aws ec2 describe-addresses --region "$REGION" --query 'Addresses[].PublicIp' --output text
# EBS disks survive their instance if they weren't set to delete on termination.
check "EBS volumes" \
  aws ec2 describe-volumes --region "$REGION" --query 'Volumes[].VolumeId' --output text
# Stored images cost a little per GB-month.
check "ECR repositories" \
  aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text
# The Terraform state bucket from infra/bootstrap. It's fine to keep between sessions; remove it in RUNBOOK Part E.
check "S3 state buckets" \
  aws s3api list-buckets --query "Buckets[?starts_with(Name, 'eks-pipeline-tfstate')].Name" --output text
# Catch-all: anything still carrying our Project tag (from the provider's default_tags).
# Note: this API can keep showing a resource for a short while after it has been deleted.
check "Anything tagged Project=eks-delivery-pipeline" \
  aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --tag-filters Key=Project,Values=eks-delivery-pipeline \
    --query 'ResourceTagMappingList[].ResourceARN' --output text

echo
if [ "$FOUND" -eq 0 ]; then
  echo "ALL CLEAR"
  exit 0
else
  echo "⚠ LEFTOVERS FOUND (see above). Run terraform destroy, or delete them in the AWS console."
  exit 1
fi
