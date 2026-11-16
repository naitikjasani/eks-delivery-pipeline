# Beginner guide: what every piece is, in plain words

Read this top to bottom once. Then keep it open while you read the code.

---

## 1. The big picture in one paragraph

A developer changes some code and pushes it to GitHub. **Jenkins** notices, runs the tests, packs the app into a
**Docker** image, and stores that image in **ECR** (AWS's image storage). Then it tells **Kubernetes** (running on
AWS as **EKS**) to swap the old version for the new one, one pod at a time, so users never see an outage. If the new
version is broken, Jenkins puts the old one back automatically. **Prometheus** keeps measuring the app,
**Grafana** draws graphs of those numbers, and **Alertmanager** posts to Slack when something goes wrong. All the AWS
servers and networks were created by **Terraform** from code, so the whole thing can be deleted and recreated with
one command.

## 2. The restaurant version

| Restaurant | In this project |
|---|---|
| The recipe | Your app's code (`app/`) |
| Packing a dish in a sealed box so it tastes the same anywhere | **Docker image** |
| The storeroom for sealed boxes | **ECR** |
| The kitchen building, gas lines, doors and keys | **AWS infrastructure**: VPC, EKS, IAM |
| The architect's blueprint for the kitchen | **Terraform** code (`infra/`) |
| The head chef who keeps 2 cooks working and replaces anyone who collapses | **Kubernetes** |
| The assembly line: order → cook → taste-test → serve | **Jenkins pipeline** (`Jenkinsfile`) |
| Staff key cards that only open certain doors | **IAM** permissions |
| CCTV, thermometers and fire alarms | **Prometheus + Grafana + Alertmanager** |

---

## 3. Each tool, simply

### Linux
The operating system almost every server runs. Your containers run Linux (Alpine), the EKS nodes run Linux
(Amazon Linux 2023), and Jenkins runs Linux inside Docker. Everything you type in a terminal here is a Linux skill.

### Docker
**Problem:** "It works on my machine" but not on the server.
**Solution:** pack the app *together with* everything it needs (Node.js, libraries) into an **image**.
A running image is a **container**. The same image runs identically on your Mac, in Jenkins and on EKS.

Key ideas in our `Dockerfile`:
- **Multi-stage build:** stage 1 installs packages, stage 2 runs tests, stage 3 is the slim final image.
  The final image doesn't contain test tools, so it's smaller and safer.
- **`USER node`:** the app doesn't run as root (admin). If someone hacks the app, they get very little power.
- **Image tag = git commit SHA** (like `a1b2c3d`): every image points to the exact code it came from.

### Kubernetes (K8s)
**Problem:** running containers by hand is fragile. What if one crashes at 3 a.m.?
**Solution:** you tell Kubernetes *what you want* ("2 copies of hello-app, always"), and it keeps it true.
A crashed container gets restarted, and if a server dies its containers move to another one.

Words you must know:
- **Cluster:** a group of machines Kubernetes manages.
- **Node:** one machine in the cluster (we have 2).
- **Pod:** the smallest unit; wraps one container (our app). Pods come and go.
- **Deployment:** "keep N pods of this image running, and update them safely." (`k8s/deployment.yaml`)
- **Service:** a stable internal address (`http://hello-app`) that spreads traffic across the pods. (`k8s/service.yaml`)
- **Namespace:** a folder inside the cluster. Our app lives in `app`, monitoring in `monitoring`.
- **Rolling update:** replace pods one at a time. We set `maxUnavailable: 0`, so an old pod is only removed
  after a new one is ready. Result: zero downtime.
- **Readiness probe:** Kubernetes asks `/health/ready` "can you take traffic?". If not, no traffic is sent to that pod.
- **Liveness probe:** Kubernetes asks `/health/live` "are you alive?". If not, the container is restarted.
- **Rollback:** `kubectl rollout undo` goes back to the previous version.
- **kubectl:** the command-line remote control for Kubernetes.

### kind
"Kubernetes IN Docker". A full Kubernetes cluster running as containers on your Mac. **Free.** We practice
everything here before paying for EKS.

### AWS (Amazon Web Services)
Renting computers and services by the hour. The services we use:

| Service | What it is | What we use it for |
|---|---|---|
| **EKS** | Kubernetes, managed by AWS | AWS runs the "brain" of the cluster; we only bring the worker machines |
| **EC2** | Virtual machines | The 2 worker nodes (EKS creates them for us) |
| **ECR** | Private Docker image storage | Jenkins pushes images here; EKS pulls from here |
| **S3** | File storage | Holds Terraform's state file (its memory of what it built) |
| **IAM** | Users, roles and permissions | Who is allowed to do what (see below) |
| **VPC** | Your private network inside AWS | Where the nodes live |

### IAM (Identity and Access Management)
AWS's security guard. Every action ("push an image", "read a bucket") needs permission.
**Least privilege** means giving each identity only what it needs:
- The **cluster role** lets EKS manage AWS things for the cluster.
- The **node role** lets the worker machines join the cluster and *pull* images (not push).
- The **`jenkins-ci` user** can push to *one* ECR repository and look up *one* cluster. Inside Kubernetes it can
  only edit the `app` namespace. Even if its key leaked, the damage would be small.

### Terraform (Infrastructure as Code)
**Problem:** clicking around the AWS console is slow, error-prone and impossible to repeat exactly.
**Solution:** describe the infrastructure in code files. Terraform compares the code with what exists and makes
reality match.
- `terraform init`: download plugins, connect to the state storage.
- `terraform plan`: **preview** what would change (free, creates nothing).
- `terraform apply`: make the changes.
- `terraform destroy`: delete everything it created.
- **State:** Terraform's memory of what it built, a file kept in S3 so it's safe and shared.
- **State lock:** stops two people from running `apply` at the same time and corrupting the state.
- **Module:** a reusable folder of Terraform code. We have 4: `network`, `eks`, `ecr`, `ci-access`.

### Jenkins (CI/CD)
- **CI (Continuous Integration):** every code change is automatically tested and built.
- **CD (Continuous Delivery/Deployment):** every good build is automatically shipped.
- Jenkins reads the **`Jenkinsfile`** (pipeline as code) and runs its **stages**:
  `Preflight → Test → Build → Push to ECR → Deploy to EKS`.
- If a stage fails, the later ones don't run. A failed test means nothing broken gets shipped.
- Our Jenkins runs on your Mac (free) and checks GitHub every 2 minutes for new commits ("polling").

### Prometheus, Grafana, Alertmanager (monitoring)
- **Prometheus** visits every app's `/metrics` page every 15 seconds and stores the numbers (requests, errors,
  response times, CPU, memory). This is called *scraping*.
- **PromQL** is its query language, e.g. "errors per second over the last 2 minutes".
- **Grafana** turns those numbers into dashboards (graphs).
- **Alert rules** say things like "if more than 5% of requests fail for 1 minute, that's an alert".
- **Alertmanager** receives alerts and sends them to Slack, without spamming duplicates.
- **The four golden signals** (what's worth watching for any service): **latency**, **traffic**, **errors**,
  **saturation** (how full the machines are). Our dashboard shows all four.
- **ServiceMonitor:** a small YAML file that tells Prometheus "scrape the pods behind this Service".

---

## 4. What happens when you `git push`, step by step

1. You push a commit to GitHub.
2. Within ~2 minutes Jenkins sees the new commit and starts the pipeline.
3. **Preflight:** Jenkins works out the short commit SHA, e.g. `a1b2c3d`.
4. **Test:** `docker build --target test`. Your tests run inside a container. If one fails, the pipeline stops here.
5. **Build:** `docker build --target runtime` creates the final image `…/hello-app:a1b2c3d`.
6. **Push:** Jenkins logs into ECR with its limited key and uploads the image.
7. **Deploy:** Jenkins updates the Deployment to use the new image. Kubernetes starts 1 new pod, waits for it to be
   ready, removes 1 old pod, and repeats.
8. Jenkins waits up to 120 seconds for the rollout to finish. If the new pods never become ready, it runs
   `kubectl rollout undo` and marks the build **failed**. The old version never stopped serving.
9. Prometheus starts scraping the new pods automatically, and Grafana shows the new version's numbers.

## 5. Why it's built the cheap way (and what production would do)

| Here (cheap demo) | In a real company | Why we differ |
|---|---|---|
| Nodes in public subnets, no NAT gateway | Private subnets + NAT gateway / VPC endpoints | A NAT gateway costs more than both nodes together |
| Spot instances | Mix of on-demand and Spot | Spot is ~70% cheaper, but AWS can take the machine back at short notice. Kubernetes reschedules the pods |
| Jenkins on a laptop, with an access key | Jenkins on AWS using an IAM role (no keys) | No server to pay for. The key is deleted on `terraform destroy` |
| `kubectl port-forward` to view the app | Load balancer + domain + HTTPS | A load balancer costs money every hour |
| Prometheus keeps 6 hours, no disk | Long retention on persistent storage | Avoids disk costs |

Being able to explain this table is a strong interview signal: it shows you understand trade-offs and cost (FinOps).

---

## 6. Glossary (quick lookup)

| Term | Meaning |
|---|---|
| **Artifact** | The output of a build. For us, the Docker image |
| **Blast radius** | How much damage one mistake or leaked key can cause |
| **CrashLoopBackOff** | A pod keeps crashing, so Kubernetes waits longer and longer between restarts |
| **Declarative** | You describe *what* you want; the tool figures out *how* (Kubernetes YAML, Terraform) |
| **Drift** | Someone changed infrastructure by hand, so it no longer matches the code |
| **Error budget** | How much failure an SLO allows (99.9% → about 43 minutes per month) |
| **GitOps** | Git is the source of truth; a tool like ArgoCD pulls changes into the cluster |
| **Idempotent** | Running it twice gives the same result as running it once (`terraform apply`, `kubectl apply`) |
| **ImagePullBackOff** | Kubernetes can't download the image: wrong name/tag or missing permission |
| **Immutable tag** | Once `a1b2c3d` is pushed, it can never point to a different image |
| **Manifest** | A YAML file describing a Kubernetes object |
| **MTTR** | Mean time to recovery: how fast you fix incidents |
| **Observability** | Being able to understand what's happening inside a system from its metrics, logs and traces |
| **Pipeline** | An automated sequence of steps (test → build → deploy) |
| **SLO** | Service Level Objective, e.g. "99.9% of requests succeed" |
| **Spot instance** | Spare AWS capacity at a big discount that AWS can reclaim with 2 minutes' notice |
| **SIGTERM** | The polite "please shut down" signal Kubernetes sends a container before stopping it |
