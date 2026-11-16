# Interview prep: questions this project prepares you for

Practise answering out loud in 30–60 seconds each. Sample answers are short on purpose; say them in your own words.

---

## 1. The project pitch (memorize this shape, not the words)

> "I built a delivery pipeline that takes a commit to production on AWS EKS. Terraform creates the VPC, the EKS
> cluster on Graviton Spot nodes, an ECR repository and least-privilege IAM. Jenkins tests the code inside Docker,
> builds an image tagged with the commit SHA, pushes it to ECR and does a rolling update on EKS. If the new version
> doesn't become ready within two minutes, it rolls back automatically. Prometheus and Grafana track the golden
> signals, and Alertmanager pages Slack on error rate, latency or downtime. I kept the running cost to roughly
> fourteen cents an hour, and the whole environment is destroyed and recreated with Terraform."

Then be ready for **"walk me through what happens when you push a commit"**. Use BEGINNER_GUIDE §4.

## 2. Project-specific questions

**Why public subnets? Isn't that insecure?**
Cost: a NAT gateway costs more than both nodes. The nodes have public IPs, but the EKS security group only allows
traffic from inside the cluster, and nothing is exposed (ClusterIP services, no load balancer). In production I'd
use private subnets with a NAT gateway or VPC endpoints for ECR/S3.

**Why Spot? What happens when AWS takes a node back?**
About 70% cheaper. AWS gives a 2-minute warning, the node is drained, and Kubernetes reschedules the pods on the
other node. With 2 replicas and readiness probes, users don't notice. In production: a mix of on-demand and Spot,
several instance types, and PodDisruptionBudgets.

**How does your rollback work?**
After applying the new Deployment, Jenkins runs `kubectl rollout status --timeout=120s`. If the new pods never pass
their readiness probe, it runs `kubectl rollout undo`, which switches the Deployment back to the previous
ReplicaSet. Because `maxUnavailable` is 0, the old pods were never removed, so there was no outage.

**How is it zero-downtime?**
Four pieces: `maxUnavailable: 0` with `maxSurge: 1`; a readiness probe so traffic only goes to ready pods; a
`preStop` sleep so the Service stops routing before the pod shuts down; and the app handles SIGTERM by finishing
in-flight requests.

**Why tag images with the git SHA, and why immutable tags?**
Traceability: every running pod maps to an exact commit. With immutable tags, `a1b2c3d` can never be overwritten,
so a rollback really restores the same bytes. `latest` makes deployments unpredictable.

**How did you apply least privilege?**
The Jenkins IAM user can push to one ECR repo and describe one cluster, nothing else. Inside Kubernetes, an EKS
access entry gives it the Edit policy scoped to the `app` namespace only. It can't create namespaces or touch
monitoring. Nodes have pull-only ECR access.

**Why does Jenkins use an access key? Isn't that bad practice?**
Yes, for production. Jenkins ran on my laptop to save cost, so it couldn't use an IAM role. The key is
least-privilege and deleted by `terraform destroy`. On AWS I'd run Jenkins with an instance profile, or use
OIDC federation from the CI system, so there are no long-lived keys at all.

**How do you manage Terraform state?**
Remote state in an S3 bucket with versioning, encryption and public access blocked, plus S3-native locking
(`use_lockfile`, Terraform ≥ 1.10). Before that, people used a DynamoDB table for locking. The bucket itself is
created by a small bootstrap config with local state, because a bucket can't store the state of its own creation.

**What would you add next?**
Helm or Kustomize for environments; ArgoCD for GitOps (Jenkins builds, ArgoCD deploys, which is what I used at
Bajaj); HPA autoscaling; Trivy image scanning as a pipeline gate; private subnets; OIDC instead of keys;
centralized logs (Loki or ELK); and tflint/checkov in CI.

## 3. Core concept questions

### Docker
- **Image vs container?** An image is the read-only template; a container is a running instance of it.
- **Why multi-stage builds?** Smaller, safer final images: build tools and tests don't ship.
- **CMD vs ENTRYPOINT?** ENTRYPOINT is the fixed executable; CMD gives default arguments (or the default command) that can be overridden.
- **How do you make images smaller?** Alpine/distroless base, multi-stage, `npm ci --omit=dev`, `.dockerignore`, fewer layers.
- **Layer caching?** Copy `package*.json` and install *before* copying source, so code changes don't reinstall dependencies.

### Kubernetes
- **Pod vs Deployment vs ReplicaSet?** A Deployment manages ReplicaSets (one per version), which keep N pods running.
- **Service types?** ClusterIP (internal), NodePort (port on every node), LoadBalancer (cloud LB), ExternalName.
- **Readiness vs liveness?** Readiness controls traffic; liveness triggers restarts. A wrong liveness probe causes restart loops.
- **Requests vs limits?** Requests are used for scheduling (guaranteed); limits are the ceiling. Going over the memory limit gets the container OOMKilled; going over CPU gets it throttled.
- **ConfigMap vs Secret?** Both inject config; Secrets are for sensitive values (base64, not encryption by default; use KMS or an external secrets manager).
- **How do you debug a failing pod?** `kubectl get pods` → `describe pod` (Events) → `logs` / `logs --previous` → `exec` → check probes, image, resources.
- **CrashLoopBackOff vs ImagePullBackOff vs Pending?** The app keeps crashing / the image can't be pulled / no node fits (resources, taints, affinity).
- **What does EKS manage?** The control plane (API server, etcd, scheduler) across AZs. You manage the nodes (or use Fargate) and the workloads.
- **HPA?** Horizontal Pod Autoscaler: adds or removes pods based on CPU, memory or custom metrics.

### Terraform
- **plan vs apply?** `plan` previews, `apply` executes. Always review the plan.
- **What is state and why remote?** Terraform's record of real resources. Remote state means it's shared, locked, versioned and not on a laptop.
- **Drift?** Real infrastructure changed outside Terraform; `plan` shows it, and `apply` brings it back to match the code.
- **Modules?** Reusable groups of resources with inputs and outputs.
- **`terraform import`?** Bring an existing resource under Terraform management.
- **count vs for_each?** `for_each` keys by name, so removing one item doesn't shift the others.
- **Secrets in Terraform?** Mark outputs `sensitive`, encrypt state, prefer secret managers, and don't hardcode secrets in `.tf` files.

### Jenkins / CI/CD
- **Declarative vs scripted pipeline?** Declarative is structured (`pipeline { stages {...} }`) and easier to read; scripted is full Groovy.
- **Agent?** The machine or container where stages run.
- **How do you handle secrets?** The Jenkins credentials store + `withCredentials`, which masks them in logs. Never echo them.
- **Webhook vs polling?** A webhook is a push from GitHub (instant, needs a public URL); polling checks on a schedule.
- **Continuous delivery vs deployment?** Delivery means every build is deployable (with a manual approval); deployment means it ships automatically.
- **Push-based (Jenkins `kubectl apply`) vs pull-based GitOps (ArgoCD)?** GitOps keeps the cluster matching Git and the CI system needs no cluster credentials.

### AWS / IAM
- **IAM user vs role?** A user has long-lived credentials; a role is assumed, gives temporary credentials, and is preferred.
- **Policy evaluation?** Default deny → an explicit allow grants access → an explicit deny always wins.
- **IRSA / EKS Pod Identity?** Gives a specific pod an IAM role, so pods don't share the node's permissions.
- **Security group vs NACL?** A security group is stateful, per instance/ENI, allow rules only. A NACL is stateless, per subnet, allow and deny rules.
- **S3 security basics?** Block public access, encryption, versioning, bucket policies, least-privilege IAM.
- **ECR vs Docker Hub?** ECR is private, IAM-integrated, has scanning, and pulls stay inside AWS.

### Monitoring
- **Metrics vs logs vs traces?** Metrics are numbers over time (cheap, good for alerting); logs are events (detail); traces follow one request across services.
- **Pull vs push?** Prometheus pulls (scrapes); it discovers targets from Kubernetes.
- **Golden signals?** Latency, traffic, errors, saturation.
- **What makes a good alert?** It fires on user-facing symptoms, is actionable, and isn't noisy, with severity routing.
- **SLO / error budget?** Target reliability (99.9%) and the allowed failure that comes with it. This links to your OZi SLO work.
- **Why not alert on CPU at 80%?** It isn't a user symptom. Alert on errors and latency; use CPU for capacity planning.

### Linux: commands to know cold
| Task | Command |
|---|---|
| Processes, CPU, memory | `top` / `htop`, `ps aux \| grep node`, `free -h` |
| Disk | `df -h`, `du -sh *` |
| Ports / connections | `ss -tulpn` (or `netstat -tulpn`), `curl -v`, `nc -zv host port` |
| Services and logs | `systemctl status nginx`, `journalctl -u nginx -f`, `tail -f /var/log/...` |
| Search text | `grep -rn "error" .`, `awk '{print $1}'`, `sort \| uniq -c` |
| Permissions | `chmod 755 file`, `chown user:group file`, `ls -l` (rwx) |
| Networking | `ip a`, `dig example.com`, `ping`, `traceroute` |
| Kill a process | `kill <pid>` (SIGTERM), `kill -9 <pid>` (SIGKILL, last resort) |
| SSH | `ssh -i key.pem ec2-user@host`, `scp file host:/path` |

## 4. Linking to your work experience

| They ask about… | Connect it to |
|---|---|
| Kubernetes / GitOps | Bajaj: ArgoCD deployments to EKS; this project: Jenkins push-based deploys, and you can compare the two |
| Monitoring / incidents | Bajaj: ELK + Kibana, 40% lower MTTR. OZi: SLOs, error budgets, Slack alerts. This project: Prometheus/Grafana |
| Reliability | OZi: SQS FIFO + claim-based redrive, which stopped duplicate wallet deductions (idempotency) |
| IAM / security | OZi: least-privilege SQS access. This project: namespace-scoped Jenkins access. Ekayu: deny-by-default database security |
| Cost awareness | This project: Spot, Graviton, no NAT/LB, ~$0.14/hour |

## 5. Questions to ask them at the end
- "What does your deployment pipeline look like today, and what's the biggest pain point?"
- "How do you manage Terraform across environments: workspaces, separate state, Terragrunt?"
- "How is on-call organized, and how are alerts tuned?"
- "What would success look like for this role in the first 3 months?"
