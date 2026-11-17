# variables.tf: inputs for the ECR module.

variable "repository_name" {
  description = "Name of the ECR repository (must match the name used in the Jenkinsfile)"
  type        = string
  default     = "hello-app"
}

variable "keep_images" {
  description = "How many of the newest images to keep. Older ones are deleted automatically to keep storage cost tiny."
  type        = number
  default     = 5
}
