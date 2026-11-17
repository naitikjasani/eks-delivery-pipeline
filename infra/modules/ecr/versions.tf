# versions.tf: version requirements for this module.
# A module has no provider block of its own; it uses the "aws" provider configured in envs/dev.
# Declaring the versions here makes the module refuse to run with an incompatible Terraform or provider.
terraform {
  # >= 1.10 matches the root configuration (needed there for S3-native state locking).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never 7.0 (major versions can break things)
    }
  }
}
