# variables.tf: inputs for the ci-access module (the least-privilege identity Jenkins uses).

variable "user_name" {
  description = "Name of the IAM user Jenkins authenticates as"
  type        = string
  default     = "jenkins-ci"
}

variable "ecr_repository_arn" {
  description = "ARN of the only ECR repository Jenkins may push to"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster Jenkins deploys to"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster (Jenkins may only describe this one cluster)"
  type        = string
}

variable "app_namespace" {
  description = "The only Kubernetes namespace Jenkins may change"
  type        = string
  default     = "app"
}
