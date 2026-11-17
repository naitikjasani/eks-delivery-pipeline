# outputs.tf: values printed after `terraform apply`.

# Copy this into infra/envs/dev/backend.hcl as the "bucket" value.
output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state"
  value       = aws_s3_bucket.tfstate.bucket
}
