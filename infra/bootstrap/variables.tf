# variables.tf: inputs for the bootstrap folder. Defaults mean you can run it with no tfvars file.

variable "region" {
  description = "AWS region for the state bucket. Keep it the same as the cluster's region."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Your name, added as the Owner tag on every resource so you know who created it."
  type        = string
  default     = "naitik"
}
