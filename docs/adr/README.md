# Architecture Decision Records

Short records of the important design decisions: the context, what was decided, what it costs, and what a
production system would do instead. Format: *Context → Decision → Consequences → In production*.

| # | Decision | Status |
|---|---|---|
| [0001](0001-public-subnets-no-nat.md) | Nodes in public subnets, no NAT gateway | Accepted |
| [0002](0002-graviton-spot-nodes.md) | Graviton (ARM) Spot instances for worker nodes | Accepted |
| [0003](0003-local-jenkins-scoped-key.md) | Local Jenkins with a least-privilege, namespace-scoped IAM key | Accepted |
| [0004](0004-immutable-sha-image-tags.md) | Image tag = git SHA, immutable ECR tags | Accepted |
| [0005](0005-s3-native-state-locking.md) | S3 remote state with native lock files (no DynamoDB) | Accepted |
| [0006](0006-push-based-deploys.md) | Push-based deploys from Jenkins instead of GitOps | Accepted |
| [0007](0007-plain-yaml-over-helm.md) | Plain Kubernetes YAML for the app instead of a Helm chart | Accepted |
| [0008](0008-grafana-memory-limit.md) | Grafana memory limit raised from 256Mi to 1Gi after measuring | Accepted |
