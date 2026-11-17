# variables.tf: inputs for the network module.

variable "name" {
  description = "Name prefix for the network resources (used in their Name tags)"
  type        = string
}

variable "vpc_cidr" {
  description = "IP address range of the VPC. /16 = 65,536 addresses, plenty of room for subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "EKS cluster name. Used in the subnet tag that tells Kubernetes which subnets belong to the cluster."
  type        = string
}
