# versions.tf: Terraform/provider versions, the remote state backend, and the AWS provider for the dev environment.
terraform {
  # >= 1.10 is required for S3-native state locking (use_lockfile = true in backend.hcl).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never 7.0 (major versions can break things)
    }
  }

  # State lives in the S3 bucket created by infra/bootstrap. The block is deliberately EMPTY:
  # the bucket name contains your account ID, so the settings come from a local, gitignored file:
  #   terraform init -backend-config=backend.hcl        (copy backend.hcl.example first)
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Tags added to every resource automatically, so leftovers are easy to find
  # (scripts/teardown-check.sh searches for Project=eks-delivery-pipeline) and costs easy to attribute.
  default_tags {
    tags = {
      Project     = "eks-delivery-pipeline"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
