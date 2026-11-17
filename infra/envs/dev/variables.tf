# variables.tf: inputs for the dev environment. Real values go in terraform.tfvars (gitignored);
# see terraform.tfvars.example.

variable "region" {
  description = "AWS region for everything"
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Your name, added as the Owner tag on every resource"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-pipeline-dev"
}

# No default on purpose: you must consciously pick the newest version in STANDARD support
# (aws eks describe-cluster-versions --region ap-south-1 --output table). A version in extended
# support costs $0.60/hour instead of $0.10/hour.
variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. \"1.37\" (must be in STANDARD support)"
  type        = string
}

variable "public_access_cidrs" {
  description = "Who may reach the Kubernetes API from the internet. Use your own public IP as x.x.x.x/32."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "capacity_type" {
  description = "SPOT (cheapest) or ON_DEMAND (use only if Spot capacity is unavailable)"
  type        = string
  default     = "SPOT"
}

variable "node_instance_types" {
  description = "Graviton (ARM) instance types for the worker nodes"
  type        = list(string)
  default     = ["t4g.medium", "t4g.large"]
}
