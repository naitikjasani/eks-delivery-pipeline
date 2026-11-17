# outputs.tf: values other modules need from the network.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

# Passed to the EKS module: the cluster and its nodes live in these subnets.
output "public_subnet_ids" {
  description = "IDs of the 2 public subnets"
  value       = aws_subnet.public[*].id
}
