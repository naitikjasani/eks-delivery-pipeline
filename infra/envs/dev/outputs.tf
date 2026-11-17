# outputs.tf: values you need after `terraform apply` (RUNBOOK C2 and C4).
# Show them again any time with: terraform -chdir=infra/envs/dev output

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name (Jenkins global env var CLUSTER_NAME)"
  value       = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "Where Jenkins pushes images (Jenkins global env var ECR_REPO_URL)"
  value       = module.ecr.repository_url
}

output "jenkins_access_key_id" {
  description = "Jenkins credential aws-access-key-id"
  value       = module.ci_access.access_key_id
}

# Hidden in normal output. Read it deliberately with: terraform output -raw jenkins_secret_access_key
output "jenkins_secret_access_key" {
  description = "Jenkins credential aws-secret-access-key"
  value       = module.ci_access.secret_access_key
  sensitive   = true
}

# A ready-to-copy command that points kubectl at the new cluster.
output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
