# ADR 0003: Local Jenkins with a least-privilege, namespace-scoped IAM key

**Status:** Accepted

## Context
Jenkins needs to push images to ECR and deploy to EKS. Running Jenkins on EC2 would let it use an IAM role (no
keys), but would add an always-on instance to the bill. The owner's laptop is free.

## Decision
Run Jenkins in Docker on the laptop. Terraform creates a dedicated IAM user `jenkins-ci` whose inline policy allows
only: `ecr:GetAuthorizationToken` (which AWS requires on `*`), push/pull actions on the **one** `hello-app`
repository, and `eks:DescribeCluster` on the **one** cluster. Inside Kubernetes, an EKS access entry grants
`AmazonEKSEditPolicy` **scoped to namespace `app`**. The namespace itself is created by an admin, so Jenkins
never needs cluster-wide rights.

## Consequences
- $0 for CI infrastructure.
- A long-lived access key exists. It is stored in Jenkins credentials (masked in logs) and in Terraform state
  (encrypted in S3), and `terraform destroy` deletes it.
- Blast radius if the key leaked: an attacker could push images to `hello-app` and change objects in namespace
  `app`, so they could deploy a malicious version of the app. They could not touch other AWS services, other
  namespaces, Secrets elsewhere, or cluster-wide objects.
- Jenkins runs as root with the host's Docker socket. This is acceptable only because it's a local, non-exposed laptop.

## In production
CI runs on AWS with an IAM role (instance profile / IRSA / EKS Pod Identity), or uses OIDC federation from the CI
system, so there are no long-lived keys at all. Builds run on rootless builders, and images are signed and
verified by an admission controller.

Implemented in [`infra/modules/ci-access/main.tf`](../../infra/modules/ci-access/main.tf) and [`Jenkinsfile`](../../Jenkinsfile).
