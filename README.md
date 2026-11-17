# Cloud-Native Delivery Pipeline on AWS EKS

**Commit → tested → containerized → deployed to Kubernetes on AWS, with automatic rollback and alerting.**
Infrastructure is 100% Terraform, CI/CD is Jenkins, monitoring is Prometheus + Grafana + Alertmanager.
Built to run for about **$0.14/hour** and be destroyed with one command.

`AWS (EKS · ECR · IAM · S3 · VPC · EC2)` · `Terraform` · `Kubernetes` · `Docker` · `Jenkins` · `Prometheus` · `Grafana` · `Alertmanager` · `Linux` · `Node.js`

> 📸 Screenshots and a demo recording are in [`docs/screenshots/`](docs/screenshots/).
> The environment is torn down between demos to avoid cloud costs. `terraform apply` recreates it in ~15 minutes.

---

## What it does

```
 git push
    │
    ▼
 GitHub ◄── polled every 2 min ── Jenkins (Docker, local)
                                     │
             ┌───────────────────────┼─────────────────────────────────────────────┐
             │ 1 Test      docker build --target test     (tests run inside Docker)│
             │ 2 Build     image tagged with the git SHA  (e.g. hello-app:a1b2c3d) │
             │ 3 Push  ────────────────────────────────►  Amazon ECR (immutable)   │
             │ 4 Deploy    kubectl apply → rolling update on EKS                   │
             │ 5 Verify    rollout status 120s → on failure: kubectl rollout undo  │
             └─────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
 ┌──────────────────────── AWS · ap-south-1 · VPC (Terraform) ────────────────────────┐
 │  EKS cluster  ──  2 × Graviton (ARM) Spot nodes                                    │
 │   ├─ namespace app:         hello-app ×2  (readiness/liveness, non-root, limits)   │
 │   └─ namespace monitoring:  Prometheus ─► Alertmanager ─► Slack #alerts            │
 │                             Grafana "Golden Signals" dashboard                     │
 │  IAM: cluster role · node role (ECR pull-only) · jenkins-ci (1 repo + 1 namespace) │
 │  S3: Terraform remote state (versioned, encrypted, native locking)                 │
 └────────────────────────────────────────────────────────────────────────────────────┘
```

## Highlights

- **Infrastructure as Code:** modular Terraform (`network`, `eks`, `ecr`, `ci-access`) with remote state in S3
  and S3-native state locking. No click-ops.
- **Zero-downtime deploys:** `maxUnavailable: 0`, readiness probes, a `preStop` delay and graceful SIGTERM handling.
- **Automatic rollback:** if new pods aren't Ready within 120 s, Jenkins runs `kubectl rollout undo` and fails the build.
- **Traceable, immutable artifacts:** every image is tagged with its commit SHA, and ECR tags can't be overwritten.
- **Least privilege:** Jenkins' IAM identity can push to one ECR repo and edit one Kubernetes namespace, nothing else
  (EKS access entries, no `aws-auth` ConfigMap). Nodes can only *pull* images.
- **Observability:** the app exposes Prometheus metrics; a Grafana dashboard shows the four golden signals; alerts for
  error rate, p95 latency, app down and restart loops go to Slack.
- **Cost-engineered:** Graviton Spot nodes, no NAT gateway, no load balancer, no CloudWatch/KMS extras, a cluster
  pinned to standard support, Jenkins on a laptop. Everything is practised on a free local `kind` cluster first.

## Cost

| While the EKS cluster exists | Per hour |
|---|---|
| EKS control plane | $0.10 |
| 2 × t4g.medium Spot nodes | ~$0.02 |
| 2 public IPv4 addresses + 40 GB of node disk | ~$0.015 |
| S3 state, ECR images | ~$0.00 |
| **Total** | **≈ $0.14/hour (≈ ₹12)**, and $0 after `terraform destroy` |

The full demo (build, record, destroy) needs about 3 cluster-hours. Prices are approximate (ap-south-1); check the AWS pricing pages.

| Production would use… | Here instead, to save cost |
|---|---|
| Private subnets + NAT gateway | Public subnets, cluster-only security group |
| Load balancer + domain + TLS | `kubectl port-forward` |
| Jenkins on AWS with an IAM role / OIDC | Local Jenkins with a least-privilege key deleted on destroy |
| On-demand + Spot mix, PodDisruptionBudgets | Spot only |
| Persistent Prometheus storage | 6 h retention in memory |

## Repository layout

| Path | What's inside |
|---|---|
| `app/` | Node.js service with `/`, `/health/live`, `/health/ready`, `/metrics`, `/error`, `/slow` + tests + multi-stage Dockerfile |
| `k8s/` | Deployment and Service manifests |
| `monitoring/` | kube-prometheus-stack values, ServiceMonitor, alert rules, Grafana dashboard |
| `jenkins/` | Local Jenkins image (docker CLI, AWS CLI, kubectl) + compose file |
| `Jenkinsfile` | The pipeline: Preflight → Test → Build → Push → Deploy (+ auto rollback) |
| `infra/bootstrap/` | S3 bucket for Terraform state |
| `infra/modules/` | `network`, `eks`, `ecr`, `ci-access` |
| `infra/envs/dev/` | The environment that wires the modules together |
| `kind/`, `scripts/` | Free local cluster, deploy helpers, traffic generator, teardown checker |
| `docs/` | Runbook, beginner guide, interview prep, screenshots |

## Quick start

> Full, beginner-level instructions: **[docs/RUNBOOK.md](docs/RUNBOOK.md)**.

**Free, local (kind):**
```bash
cd app && npm ci && npm test && cd ..
./scripts/kind-up.sh && ./scripts/kind-deploy.sh
kubectl -n app port-forward svc/hello-app 8081:80     # http://localhost:8081
```

**AWS (paid while running):**
```bash
terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply
cp infra/envs/dev/backend.hcl.example infra/envs/dev/backend.hcl            # fill in the bucket name
cp infra/envs/dev/terraform.tfvars.example infra/envs/dev/terraform.tfvars  # fill in the values
terraform -chdir=infra/envs/dev init -backend-config=backend.hcl
terraform -chdir=infra/envs/dev plan
terraform -chdir=infra/envs/dev apply
aws eks update-kubeconfig --region ap-south-1 --name eks-pipeline-dev
```

**Teardown (always):**
```bash
helm -n monitoring uninstall monitoring; kubectl delete namespace monitoring app
terraform -chdir=infra/envs/dev destroy
./scripts/teardown-check.sh        # must print ALL CLEAR
```

## Demos

| # | Demo | What it proves |
|---|---|---|
| 1 | First deploy: commit → running pods | End-to-end CI/CD into EKS via ECR |
| 2 | Change the code while traffic flows through the Service | Zero-downtime rolling update |
| 3 | Release that passes tests but crashes at startup | Automatic rollback; old pods kept serving |
| 4 | Generate 5xx traffic | Grafana shows the spike; Slack gets FIRING, then RESOLVED |
| 5 | Use Jenkins' credentials against S3 / the monitoring namespace | Least privilege: AccessDenied / Forbidden |

## Pinned versions

| Component | Version |
|---|---|
| Terraform | ≥ 1.10 (built and validated with 1.17.2) |
| AWS provider | ~> 6.0 (locked to 6.73.0 in `.terraform.lock.hcl`) |
| Kubernetes (EKS) | 1.37: newest standard-support version in November 2026 (standard support until Dec 1, 2027). Re-check with `aws eks describe-cluster-versions` before `apply` |
| kube-prometheus-stack | 93.3.0 (see [`monitoring/README.md`](monitoring/README.md)) |
| Node.js | 24 LTS (`node:24-alpine`) |
| Express / prom-client | 5.x / 15.x |
| Jenkins | `jenkins/jenkins:lts-jdk21` |

## Learn more
- [docs/BEGINNER_GUIDE.md](docs/BEGINNER_GUIDE.md): every tool and concept in plain words
- [docs/RUNBOOK.md](docs/RUNBOOK.md): step-by-step setup, demos, teardown, troubleshooting
- [docs/INTERVIEW_PREP.md](docs/INTERVIEW_PREP.md): questions this project answers
- [PROJECT.md](PROJECT.md): the full build specification
