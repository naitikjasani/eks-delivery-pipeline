# main.tf: the S3 bucket that stores Terraform state for infra/envs/dev.
#
# Why remote state at all? The state file is Terraform's memory of what it created. Keeping it in S3
# (instead of on one laptop) makes it durable, versioned, encrypted and shareable.
#
# State locking: Terraform >= 1.10 locks the state with a small lock FILE next to it in S3
# (use_lockfile = true in backend.hcl). That stops two `terraform apply` runs from corrupting the state at once.
# The older approach was a separate DynamoDB table for locks; we don't need one any more,
# which is one less resource to create, pay for, and forget to delete.

# Looks up the AWS account ID of whoever runs Terraform. Reading data creates nothing.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  # S3 bucket names are global across ALL AWS accounts, so the account ID makes ours unique.
  bucket = "eks-pipeline-tfstate-${data.aws_caller_identity.current.account_id}"

  # Allows `terraform destroy` to delete the bucket even though it still contains state files
  # (and their old versions). Normally you'd protect state, but this demo must be fully removable (RUNBOOK Part E).
  force_destroy = true
}

# Versioning keeps every previous copy of the state file, so a bad or corrupted state write can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest. State can contain secrets (e.g. the Jenkins access key).
# AES256 = S3-managed keys (SSE-S3), which are free. A KMS key would cost money and isn't needed here.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block every form of public access. State must never be readable from the internet.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true # reject requests that try to add public ACLs
  block_public_policy     = true # reject bucket policies that would grant public access
  ignore_public_acls      = true # ignore any public ACLs that somehow exist
  restrict_public_buckets = true # only AWS services and the account itself may access it, even with a public policy
}
