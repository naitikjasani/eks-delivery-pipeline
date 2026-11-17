# outputs.tf: the Jenkins credentials. Paste them into Jenkins (RUNBOOK C4); never commit them anywhere.

output "access_key_id" {
  description = "Access key ID for the jenkins-ci user (Jenkins credential: aws-access-key-id)"
  value       = aws_iam_access_key.jenkins.id
}

# sensitive = true hides the value in plan/apply output. Read it deliberately with:
#   terraform output -raw jenkins_secret_access_key
output "secret_access_key" {
  description = "Secret access key for the jenkins-ci user (Jenkins credential: aws-secret-access-key)"
  value       = aws_iam_access_key.jenkins.secret
  sensitive   = true
}
