# main.tf: the dev environment. It wires the four modules together:
#   network (VPC) → eks (cluster + nodes) → ecr (image registry) → ci-access (Jenkins identity)
# Outputs of one module become inputs of the next, which also tells Terraform the order to create them in.

locals {
  # Prefix for resource Name tags, e.g. "eks-pipeline-dev-vpc".
  name = var.cluster_name
}

module "network" {
  source = "../../modules/network"

  name         = local.name
  cluster_name = var.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.network.public_subnet_ids
  public_access_cidrs = var.public_access_cidrs
  capacity_type       = var.capacity_type
  node_instance_types = var.node_instance_types
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "hello-app"
}

module "ci_access" {
  source = "../../modules/ci-access"

  user_name          = "jenkins-ci"
  ecr_repository_arn = module.ecr.repository_arn
  cluster_name       = module.eks.cluster_name
  cluster_arn        = module.eks.cluster_arn
  app_namespace      = "app"
}
