# outputs.tf: values other modules and the dev environment need from the cluster.

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

# Used by ci-access to scope the Jenkins user's eks:DescribeCluster permission to this one cluster.
output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version the cluster runs"
  value       = aws_eks_cluster.this.version
}
