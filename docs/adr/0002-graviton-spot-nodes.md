# ADR 0002: Graviton (ARM) Spot instances for worker nodes

**Status:** Accepted

## Context
Two worker nodes must run the app (2 replicas) and the full monitoring stack. Images are built on an Apple
Silicon (arm64) Mac. On-demand x86 instances would cost several times more and need cross-platform image builds.

## Decision
A managed node group with `capacity_type = "SPOT"`, `ami_type = "AL2023_ARM_64_STANDARD"` and two instance types,
`t4g.medium` and `t4g.large`. Scaling is capped at `max_size = 2`. The disk is 20 GB.

## Consequences
- About 70% cheaper than on-demand, and ARM matches the build machine, so no cross-compiling.
- Two instance types give Spot two capacity pools, which makes a node more likely to be available.
- AWS can reclaim a Spot node with 2 minutes' warning. Kubernetes reschedules its pods onto the other node.
  If both are reclaimed at once, the app is down until capacity returns, and `HelloAppDown` fires.
- Rejected: `t4g.small` (2 GiB is too little for Prometheus + Grafana), `m6g.medium` (ENI limits allow only 8 pods per node).
- `ON_DEMAND` stays available as a one-line tfvars fallback if Spot capacity runs out.

## In production
A mix of on-demand (base capacity) and Spot (burst), several instance families and AZs, PodDisruptionBudgets,
and a node autoscaler (Karpenter or Cluster Autoscaler).

Implemented in [`infra/modules/eks/main.tf`](../../infra/modules/eks/main.tf).
