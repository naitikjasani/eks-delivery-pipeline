# variables.tf: inputs for the EKS module.

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.37\". Must be in EKS STANDARD support (extended support costs 6x more)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane's network interfaces and the worker nodes (at least 2 AZs)"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "IP ranges allowed to reach the public Kubernetes API endpoint. Set to your own IP/32 in tfvars."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the node group. Several types give Spot more pools to choose from."
  type        = list(string)
  default     = ["t4g.medium", "t4g.large"]
}

variable "capacity_type" {
  description = "SPOT (~70% cheaper, can be reclaimed) or ON_DEMAND (fallback if Spot capacity is unavailable)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "desired_size" {
  description = "Number of nodes to run normally"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes. Capped at 2 so a mistake can never scale up the bill."
  type        = number
  default     = 2
}
