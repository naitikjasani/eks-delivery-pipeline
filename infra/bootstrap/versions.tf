# versions.tf: which Terraform and provider versions this folder needs.
#
# This "bootstrap" folder creates the S3 bucket that will hold the state of everything else.
# It keeps its OWN state LOCALLY (terraform.tfstate in this folder, gitignored). That's a chicken-and-egg
# problem: the bucket can't store the state of its own creation, because it doesn't exist yet.
# So there is deliberately no backend block here.
terraform {
  # >= 1.10 is required for S3-native state locking (use_lockfile), which envs/dev relies on.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.0" = any 6.x release, but never 7.0, which could contain breaking changes.
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource created by this provider gets these tags automatically, which makes leftovers
  # easy to find (scripts/teardown-check.sh searches for Project=eks-delivery-pipeline) and costs easy to track.
  default_tags {
    tags = {
      Project     = "eks-delivery-pipeline"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}
