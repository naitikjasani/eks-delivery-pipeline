# ADR 0001: Nodes in public subnets, no NAT gateway

**Status:** Accepted

## Context
EKS nodes need outbound internet access to pull images and reach AWS APIs. The textbook layout puts nodes in
private subnets and routes outbound traffic through a NAT gateway. A NAT gateway costs about $0.056/hour plus
data processing, which is more than both Spot worker nodes combined. The project's budget target is ≈ $0.14/hour.

## Decision
Put the nodes in **two public subnets** (two AZs) with `map_public_ip_on_launch = true`, and route `0.0.0.0/0`
through a free internet gateway. No NAT gateway, no load balancer. The app is a `ClusterIP` Service, reached
with `kubectl port-forward`. The Kubernetes API endpoint is restricted to the owner's IP via `public_access_cidrs`.

## Consequences
- Running cost stays near the EKS control-plane fee.
- Nodes have public IPs. Inbound traffic is still blocked: the EKS-managed cluster security group only allows
  traffic from inside the cluster, and nothing is exposed through a Service.
- There is one less layer of defence than a private-subnet design.

## In production
Private subnets for nodes, plus a NAT gateway per AZ, or VPC endpoints for ECR, S3 and STS so that image pulls
never leave the AWS network. An ingress controller behind a load balancer with TLS would expose the app.

Implemented in [`infra/modules/network/main.tf`](../../infra/modules/network/main.tf).
