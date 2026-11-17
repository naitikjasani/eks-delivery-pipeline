# main.tf: the EKS cluster (Kubernetes control plane run by AWS), its worker nodes, and their IAM roles.
#
# Written as plain resources (no community module) so every billable thing is visible:
#   aws_eks_cluster     → $0.10/hour (the control plane)
#   aws_eks_node_group  → the EC2 Spot instances + their 20 GB disks
# Everything else here (IAM roles, policy attachments) is free.

# ---------------------------------------------------------------------------------------------
# Cluster IAM role: lets the EKS service itself manage AWS resources (network interfaces, etc.) for the cluster.
# ---------------------------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  # Trust policy: WHO may assume (use) this role. Only the EKS service.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# WHAT the role may do: AWS's managed policy with exactly the permissions an EKS control plane needs.
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------------------------
# The cluster (control plane).
# ---------------------------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids
    # Public endpoint: lets kubectl on your Mac (and local Jenkins) reach the API server over the internet.
    endpoint_public_access = true
    # Private endpoint: nodes talk to the API server inside the VPC instead of going out and back in.
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs # set to your own IP/32 in tfvars for safety
  }

  access_config {
    authentication_mode                         = "API" # modern access entries, no aws-auth ConfigMap
    bootstrap_cluster_creator_admin_permissions = true  # whoever runs terraform gets cluster-admin
  }

  upgrade_policy {
    support_type = "STANDARD" # never pay extended-support pricing
  }

  # enabled_cluster_log_types intentionally omitted → no CloudWatch cost
  # encryption_config intentionally omitted → no KMS key cost

  # Make sure the role has its permissions BEFORE the cluster is created, and keeps them until the cluster
  # is fully deleted on destroy. Otherwise EKS could get stuck without the rights to clean up.
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ---------------------------------------------------------------------------------------------
# Node IAM role: assumed by the EC2 worker instances.
# ---------------------------------------------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  # Only EC2 instances may assume this role (the node group's instances get it through an instance profile).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Lets the kubelet on each node join the cluster and describe its own instance.
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Lets the AWS VPC CNI plugin give each pod a real VPC IP address (it manages network interfaces on the node).
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Lets nodes PULL images from ECR. "PullOnly" is tighter than the older "ReadOnly" policy, which also allows
# listing and describing every repository and image. Nodes only ever need to download images (least privilege).
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# ---------------------------------------------------------------------------------------------
# Managed node group: EKS creates and looks after the EC2 worker instances for us.
# ---------------------------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # Amazon Linux 2023 for ARM64 (Graviton). ARM matches the Apple Silicon Mac where Jenkins builds the
  # images, so no cross-compiling is needed, and Graviton is cheaper than x86 for the same performance.
  ami_type = "AL2023_ARM_64_STANDARD"

  # SPOT = spare AWS capacity at ~70% off. AWS can reclaim a node with 2 minutes' notice; Kubernetes then
  # reschedules its pods on the other node. Fine for a demo; switch to ON_DEMAND only if Spot is unavailable.
  capacity_type = var.capacity_type

  # Why t4g.medium/large (2 vCPU, 4 or 8 GiB)?
  #   - Not t4g.small: 2 GiB is too little memory for Prometheus + Grafana + the app together.
  #   - Not m6g.medium: it allows only 8 pods per node because of its network-interface (ENI) limits,
  #     and the monitoring stack alone needs more than that.
  # Listing two types gives Spot two capacity pools to pick from, so a node is more likely to be available.
  instance_types = var.node_instance_types

  # Root disk per node, in GB. 20 GB is enough for the OS and container images, and keeps EBS cost tiny.
  disk_size = 20

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # During node upgrades, replace at most one node at a time, so the other keeps serving.
  update_config {
    max_unavailable = 1
  }

  # The node role must have all three policies before nodes start (or they can't join the cluster),
  # and must keep them until the nodes are gone on destroy (or they can't be cleaned up).
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
