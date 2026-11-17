# outputs.tf: values Jenkins and the ci-access module need.

# e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com/hello-app → Jenkins global env var ECR_REPO_URL.
output "repository_url" {
  description = "Full URL of the repository, used to tag and push images"
  value       = aws_ecr_repository.this.repository_url
}

# Used by ci-access to allow pushes to THIS repository only.
output "repository_arn" {
  description = "ARN of the repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository"
  value       = aws_ecr_repository.this.name
}
