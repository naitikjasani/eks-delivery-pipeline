# PROJECT.md: Cloud-Native Delivery Pipeline on AWS EKS

> **Who this is for:** coding agents that will build this repository, and the owner (a beginner in DevOps)
> who must understand every part of it for an interview.
>
> **Rules for agents** (also in `AGENTS.md`): build phase by phase, never create paid AWS resources,
> never commit secrets, comment every important line with *why*, and run each phase's **Verify** step.

---

## 0. Table of contents

1. What we are building
2. Goals and non-goals
3. Cost rules (hard constraints)
4. Fixed names and versions
5. Final repository layout
6. Phase 1: The app (`app/`)
7. Phase 2: Kubernetes manifests (`k8s/`) + local cluster (`kind`)
8. Phase 3: Monitoring (`monitoring/`)
9. Phase 4: Jenkins (`jenkins/` + `Jenkinsfile`)
10. Phase 5: Terraform (`infra/`)
11. Phase 6: Helper scripts (`scripts/`)
12. Phase 7: Documentation polish
13. Definition of done (full checklist)
14. Appendix: why each design decision was made

---

## 1. What we are building

A small web app (`hello-app`) and **the complete machinery to ship it to production on AWS**:

```
 Developer                Jenkins (runs on the owner's Mac, in Docker)              AWS (ap-south-1)
 ─────────                ───────────────────────────────────────────              ─────────────────
 git push ──► GitHub ──► 1. Test    (docker build --target test)
                         2. Build   (docker build → image tagged with git SHA)
                         3. Push    ───────────────────────────────────────────►  ECR (image registry)
                         4. Deploy  (kubectl apply + rollout status)  ─────────►  EKS cluster
                         5. If unhealthy → kubectl rollout undo (auto rollback)      ├─ namespace app:  hello-app ×2 pods
                                                                                     └─ namespace monitoring:
                                                                                          Prometheus → Alertmanager → Slack
                                                                                          Grafana dashboards
 All AWS infrastructure (VPC, EKS, ECR, IAM) is created by Terraform; state lives in S3.
```

The same Kubernetes manifests and monitoring setup must also run **for free on a local `kind` cluster**.
That's where the owner practices; the paid EKS cluster runs for only ~3 hours in total.

## 2. Goals and non-goals

**Goals**
- Every tool in the target job description is used for real: AWS, Jenkins, Terraform, Kubernetes, Docker,
  monitoring (Prometheus/Grafana/Alertmanager), Linux, EKS, S3, IAM, ECR.
- Zero-downtime rolling deploys, plus **automatic rollback** when a release is unhealthy.
- Least-privilege security: the Jenkins identity can only push to one ECR repo and edit one Kubernetes namespace.
- Cheapest possible AWS footprint (see §3), fully destroyable with one command.
- Beginner-readable: comments explain *why*, not just *what*.

**Non-goals** (do NOT build these)
- No custom domain, HTTPS, Ingress controller or load balancer.
- No Helm chart for the app (plain YAML is easier to learn).
- No GitHub Actions *deploy* workflow (Jenkins is the CI/CD tool here). A checks-only workflow (tests, lint, `terraform validate`; no credentials, never deploys) is allowed.
- No databases, no persistent volumes.
- No multiple environments (only `dev`).

## 3. Cost rules (hard constraints)

The owner has almost no budget. Target: **≈ $0.14/hour (≈ ₹12/hour) while the cluster exists, $0 when destroyed.**

| Decision | Why it saves money |
|---|---|
| Practice on local `kind` first; EKS only for the final demo | Local Kubernetes is free |
| **Graviton (ARM) Spot** nodes: `t4g.medium` / `t4g.large`, `capacity_type = "SPOT"` | ~70% cheaper than on-demand. ARM matches the owner's Apple Silicon Mac, so images need no cross-compiling |
| Nodes in **public subnets**, **no NAT gateway** | A NAT gateway costs more than both nodes combined (≈ $0.056/hr + data) |
| **No load balancer**; access via `kubectl port-forward` | Saves ≈ $0.025/hr |
| **Jenkins runs locally** in Docker on the Mac | No EC2 instance for Jenkins |
| No CloudWatch control-plane logs, no KMS key, no EBS volumes for Prometheus | Each one is a small, easily forgotten recurring cost |
| `upgrade_policy { support_type = "STANDARD" }` on the cluster | Prevents EKS *extended support* pricing ($0.60/hr instead of $0.10/hr) |
| ECR lifecycle policy (keep 5 images) + `force_delete = true` | Storage stays tiny; `terraform destroy` doesn't get stuck on images |
| S3 state bucket with `force_destroy = true` | Can be fully removed at the end |
| Provider `default_tags` on every resource | Leftovers are easy to find with `scripts/teardown-check.sh` |

**Forbidden resources: agents must never add these:**
`aws_nat_gateway`, `aws_lb`/`aws_alb`/`aws_elb`, `Service type: LoadBalancer`, Ingress controllers,
`aws_cloudwatch_log_group`, `aws_kms_key`, EBS CSI driver / PersistentVolumeClaims, `aws_eks_fargate_profile`,
`aws_instance` (for Jenkins or anything else), `aws_eip`, `aws_db_*`, a second cluster or node group,
or community modules such as `terraform-aws-modules/*`. Write plain resources so the owner sees and
understands every billable thing.

## 4. Fixed names and versions

Use these exact names everywhere so the docs and commands match.

| Thing | Value |
|---|---|
| GitHub repo | `eks-delivery-pipeline` |
| AWS region | `ap-south-1` (Mumbai), configurable via variable |
| Project tag | `Project = "eks-delivery-pipeline"` |
| EKS cluster name | `eks-pipeline-dev` |
| ECR repository | `hello-app` |
| Kubernetes app namespace | `app` |
| Kubernetes monitoring namespace | `monitoring` |
| App / Deployment / Service / container name | `hello-app` |
| App port | `3000` (container), Service port `80` |
| Helm release for monitoring | `monitoring` (chart `prometheus-community/kube-prometheus-stack`) |
| IAM user for Jenkins | `jenkins-ci` |
| Local kind cluster | `devops-lab` |
| Node.js | 24 (LTS), image `node:24-alpine` |
| Terraform | `>= 1.10` (needed for S3 native state locking) |
| AWS provider | `hashicorp/aws ~> 6.0` |
| Kubernetes version | Newest version in **standard support**. Check with `aws eks describe-cluster-versions --region ap-south-1 --output table`. Never pick one in extended support |
| kube-prometheus-stack chart | Pin to the latest version at build time (`helm search repo prometheus-community/kube-prometheus-stack`) and write the pinned version into `monitoring/README.md` |

## 5. Final repository layout

```
eks-delivery-pipeline/
├── README.md                     # Public overview (already written; update screenshots + pinned versions)
├── PROJECT.md                    # This spec
├── AGENTS.md                     # Agent rules (kept local, not committed)
├── Jenkinsfile                   # The CI/CD pipeline (repo root, so Jenkins finds it)
├── .gitignore                    # Already written
├── app/
│   ├── package.json
│   ├── package-lock.json
│   ├── .dockerignore
│   ├── Dockerfile
│   ├── src/
│   │   ├── config.js             # Reads env vars (GREETING, APP_VERSION, PORT, POD_NAME)
│   │   ├── metrics.js            # Prometheus metrics (prom-client)
│   │   ├── app.js                # Express app (exported, no listen) so tests can import it
│   │   └── server.js             # Starts the server + graceful shutdown on SIGTERM
│   └── test/
│       └── app.test.js           # node:test + supertest
├── k8s/
│   ├── deployment.yaml           # Uses literal IMAGE_PLACEHOLDER, replaced at deploy time
│   └── service.yaml
├── kind/
│   └── kind-config.yaml          # 1 control-plane + 1 worker
├── monitoring/
│   ├── README.md                 # Install commands + pinned chart version
│   ├── values.yaml               # kube-prometheus-stack settings shared by kind and EKS
│   ├── values-kind.yaml          # Small overrides needed only on kind (Docker Desktop)
│   ├── alertmanager-slack.values.example.yaml   # Template; real file is gitignored
│   ├── servicemonitor.yaml       # Tells Prometheus to scrape hello-app
│   ├── prometheusrule.yaml       # Alert rules
│   └── grafana-dashboard.yaml    # ConfigMap containing the dashboard JSON
├── jenkins/
│   ├── Dockerfile                # Jenkins + docker CLI + aws CLI + kubectl
│   ├── plugins.txt
│   └── docker-compose.yml
├── infra/
│   ├── bootstrap/                # S3 bucket for Terraform state (uses LOCAL state)
│   │   ├── versions.tf  main.tf  variables.tf  outputs.tf
│   ├── modules/
│   │   ├── network/              # VPC, 2 public subnets, IGW, routes
│   │   ├── eks/                  # Cluster, node group, cluster + node IAM roles
│   │   ├── ecr/                  # Repository + lifecycle policy
│   │   └── ci-access/            # jenkins-ci IAM user, policy, access key, EKS access entry
│   │       (each module: main.tf variables.tf outputs.tf)
│   └── envs/
│       └── dev/
│           ├── versions.tf       # terraform + provider + backend "s3" {} (empty, filled by backend.hcl)
│           ├── main.tf           # Wires the 4 modules together
│           ├── variables.tf
│           ├── outputs.tf
│           ├── backend.hcl.example
│           └── terraform.tfvars.example
├── scripts/
│   ├── kind-up.sh                # Create local cluster
│   ├── kind-deploy.sh            # Build image, load into kind, apply manifests
│   ├── kind-down.sh              # Delete local cluster
│   ├── traffic.sh                # Generate normal / error traffic for dashboards & alerts
│   └── teardown-check.sh         # Lists any billable AWS resources still alive
└── docs/
    ├── RUNBOOK.md                # Human step-by-step (already written)
    ├── BEGINNER_GUIDE.md         # Concepts explained simply (already written)
    ├── INTERVIEW_PREP.md         # Q&A (already written)
    └── screenshots/              # Owner adds PNGs here during the demo
```

---

## 6. Phase 1: The app (`app/`)

### 6.1 Behaviour

A tiny Express server (plain JavaScript, ES modules, **no build step**).

| Endpoint | Response | Purpose |
|---|---|---|
| `GET /` | `200 {"message": GREETING, "version": APP_VERSION, "pod": POD_NAME}` | Shows which version/pod answered (proves rolling updates) |
| `GET /health/live` | `200 {"status":"ok"}` | **Liveness**: "is the process alive?" |
| `GET /health/ready` | `200 {"status":"ready"}`, or `503 {"status":"shutting-down"}` after SIGTERM | **Readiness**: "should I get traffic?" |
| `GET /error` | `500 {"error":"simulated failure"}` | Lets us trigger the error-rate alert on purpose |
| `GET /slow?ms=800` | Waits `ms` (cap at 5000) then `200` | Lets us move the p95 latency graph |
| `GET /metrics` | Prometheus text format | Scraped by Prometheus |
| anything else | `404 {"error":"not found"}` | |

### 6.2 `src/config.js`
- Export an object built from env vars:
  - `port`: `Number(process.env.PORT) || 3000`
  - `greeting`: `process.env.GREETING ?? "Hello from hello-app"`
  - `version`: `process.env.APP_VERSION ?? "dev"`
  - `podName`: `process.env.POD_NAME ?? os.hostname()`
- Must NOT throw or exit on missing env vars (tests import this file).

### 6.3 `src/metrics.js`
Use `prom-client`:
- `collectDefaultMetrics()` (CPU, memory, event-loop lag).
- `http_requests_total`: Counter, labels `method`, `route`, `status_code`.
- `http_request_duration_seconds`: Histogram, same labels, buckets `[0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]`.
- Export an Express middleware that records both on `res.on("finish")`.
- **Do not record** `/metrics` or `/health/*` requests (Prometheus scrapes and kubelet probes would drown out real traffic).
- `route` label = the matched route pattern (`req.route?.path`), or `"unmatched"` for 404s. Never use the raw URL,
  because that creates unbounded label cardinality (explain this in a comment).

### 6.4 `src/app.js`
- `createApp()` returns the Express app (no `listen`). Registers JSON responses, the metrics middleware, routes above.
- Exports a function `markShuttingDown()` that flips the readiness flag.

### 6.5 `src/server.js`
- Calls `createApp().listen(config.port)` and logs one JSON line on start: `{"msg":"listening","port":3000,"version":"..."}`.
- On `SIGTERM` and `SIGINT`: call `markShuttingDown()`, log it, then `server.close()`, exit 0 when closed,
  and force-exit with code 1 after 10 s. Comment: this is what makes rolling updates zero-downtime. Kubernetes
  sends SIGTERM, we stop accepting new work, finish in-flight requests, then exit.
- Logs are single-line JSON to stdout (Kubernetes collects stdout; JSON is searchable).
- Leave this exact comment block near the top of `server.js` (the owner uses it in the "broken release" demo,
  `docs/RUNBOOK.md` → Demo 3). Tests never import `server.js`, so a startup crash here passes CI but fails in
  Kubernetes. That's exactly the kind of bug automatic rollback exists for:
  ```js
  // --- DEMO 3 (broken release) -------------------------------------------------
  // To simulate a release that passes tests but crashes in production, uncomment:
  // if (process.env.NODE_ENV === "production" && !process.env.DATABASE_URL) {
  //   console.error(JSON.stringify({ msg: "DATABASE_URL is required", level: "fatal" }));
  //   process.exit(1);
  // }
  // ------------------------------------------------------------------------------
  ```

### 6.6 `package.json`
- `"type": "module"`, `"engines": {"node": ">=24"}`.
- Dependencies: `express` (v5), `prom-client`. Dev dependency: `supertest`.
- Scripts: `"start": "node src/server.js"`, `"test": "node --test"`.
- Commit `package-lock.json` (needed for `npm ci`).

### 6.7 `test/app.test.js` (node:test + supertest)
Tests must cover:
1. `GET /` → 200 and body has `message`, `version`, `pod`.
2. `GET /health/live` → 200.
3. `GET /health/ready` → 200; after `markShuttingDown()` → 503 (use a fresh app instance per test).
4. `GET /error` → 500.
5. `GET /metrics` → 200, contains `http_requests_total`, after calling `/` once.
6. `GET /nope` → 404.

### 6.8 `Dockerfile` (multi-stage)
```dockerfile
# Stage 1: install ALL deps (incl. dev) once, cached by package*.json
FROM node:24-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Stage 2: run tests. Jenkins runs: docker build --target test .
# If a test fails, the build fails and nothing is pushed.
FROM deps AS test
COPY . .
RUN npm test

# Stage 3: small production image (no dev deps, no tests)
FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
# Run as the non-root "node" user (uid 1000); the Deployment's securityContext requires it.
# (Dockerfile comments must be on their own line, not after an instruction.)
USER node
EXPOSE 3000
CMD ["node", "src/server.js"]
```
Explain in comments: BuildKit skips stages that the target doesn't need, so a plain `docker build` (runtime
target) doesn't run tests. That's why Jenkins runs `--target test` as a separate step.

`.dockerignore`: `node_modules`, `npm-debug.log`, `test` is NOT ignored (the test stage needs it), `.git`, `*.md`.

### 6.9 Verify (Phase 1)
```bash
cd app && npm ci && npm test                                  # all tests pass
docker build --target test -t hello-app:test .                # tests pass inside Docker
docker build --target runtime --build-arg APP_VERSION=local -t hello-app:local .
docker run --rm -d -p 3000:3000 --name ha hello-app:local
curl -s localhost:3000/ && curl -s localhost:3000/metrics | head -5
docker stop ha                                                # stops within ~1s (graceful shutdown works)
docker image inspect hello-app:local --format '{{.Architecture}} {{.Size}}'   # arm64, ideally < 200MB
```

---

## 7. Phase 2: Kubernetes manifests (`k8s/`) + local cluster (`kind`)

### 7.1 `k8s/deployment.yaml`
Requirements (each needs a short *why* comment):
- `metadata.namespace: app`, labels `app: hello-app`.
- `replicas: 2`, `revisionHistoryLimit: 5`, `minReadySeconds: 5`.
- `strategy: RollingUpdate` with `maxSurge: 1`, `maxUnavailable: 0`. This is what makes deploys zero-downtime:
  old pods stay until a new one is Ready.
- Pod `securityContext`: `runAsNonRoot: true`, `runAsUser: 1000`, `seccompProfile: {type: RuntimeDefault}`.
- Container:
  - `image: IMAGE_PLACEHOLDER` (literal string; replaced by `sed` in Jenkins and `scripts/kind-deploy.sh`).
  - `imagePullPolicy: IfNotPresent`.
  - `ports: [{name: http, containerPort: 3000}]`.
  - env: `GREETING: "Hello from Kubernetes"`, `POD_NAME` from `fieldRef: metadata.name`.
  - `readinessProbe`: `httpGet /health/ready port http`, `periodSeconds: 5`, `failureThreshold: 2`.
  - `livenessProbe`: `httpGet /health/live port http`, `initialDelaySeconds: 10`, `periodSeconds: 10`, `failureThreshold: 3`.
  - `resources`: requests `cpu: 50m, memory: 64Mi`; limits `cpu: 250m, memory: 128Mi`.
  - `securityContext`: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: {drop: [ALL]}`.
  - `lifecycle.preStop.exec.command: ["sleep", "5"]`. Gives the Service time to stop routing to this pod before it shuts down.
- `terminationGracePeriodSeconds: 30`.

### 7.2 `k8s/service.yaml`
`type: ClusterIP` (internal only, which costs nothing), port `80` → `targetPort: http`, port name `http`,
selector `app: hello-app`, label `app: hello-app` (the ServiceMonitor selects on it).

**Do not** put a `Namespace` object in `k8s/`. The namespace is created once by the admin
(`kubectl create namespace app`), because the Jenkins identity is deliberately **not allowed** to create
cluster-wide objects (least privilege).

### 7.3 `kind/kind-config.yaml`
`kind: Cluster`, `apiVersion: kind.x-k8s.io/v1alpha4`, nodes: one `control-plane`, one `worker`.

### 7.4 Verify (Phase 2): local, free
```bash
./scripts/kind-up.sh                 # creates cluster devops-lab + namespace app
./scripts/kind-deploy.sh             # builds hello-app:local, kind load, applies k8s/ with image substituted
kubectl -n app rollout status deploy/hello-app --timeout=120s
kubectl -n app get pods -o wide      # 2/2 Running, READY 1/1
kubectl -n app port-forward svc/hello-app 8081:80 &
curl -s localhost:8081/
# Zero-downtime check: in one terminal run ./scripts/traffic.sh normal, in another
# kubectl -n app rollout restart deploy/hello-app → every line in the first terminal stays 200
```

---

## 8. Phase 3: Monitoring (`monitoring/`)

### 8.1 `values.yaml` (shared)
Must set, with comments:
```yaml
# Things EKS manages for us and hides. Scraping them only produces false "target down" alerts.
kubeControllerManager: { enabled: false }
kubeScheduler:         { enabled: false }
kubeEtcd:              { enabled: false }
kubeProxy:             { enabled: false }
defaultRules:
  rules:
    etcd: false
    kubeControllerManager: false
    kubeSchedulerAlerting: false
    kubeSchedulerRecording: false
    kubeProxy: false

prometheus:
  prometheusSpec:
    retention: 6h                         # demo only; keeps memory low
    scrapeInterval: 15s
    # Pick up ServiceMonitors/rules from ANY namespace without needing the Helm release label:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    resources:
      requests: { cpu: 100m, memory: 400Mi }
      limits:   { memory: 1Gi }
    # No storageSpec → emptyDir. Data is lost on restart, which is fine for a demo and avoids EBS cost.

alertmanager:
  alertmanagerSpec:
    resources:
      requests: { cpu: 10m, memory: 32Mi }
      limits:   { memory: 128Mi }

grafana:
  persistence: { enabled: false }
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL                # loads our dashboard ConfigMap
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { memory: 256Mi }
```
Do not hardcode a Grafana password. The chart creates a secret; docs show how to read it.

### 8.2 `values-kind.yaml`
```yaml
# Docker Desktop's VM doesn't support the shared root mount node-exporter wants.
prometheus-node-exporter:
  hostRootFsMount:
    enabled: false
```

### 8.3 `alertmanager-slack.values.example.yaml`
Template the owner copies to `alertmanager-slack.values.yaml` (gitignored) and pastes the webhook into:
```yaml
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: slack
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 2m
      repeat_interval: 1h
      routes:
        - receiver: "null"                # Watchdog fires forever by design (dead-man switch); don't spam Slack
          matchers: [ 'alertname = "Watchdog"' ]
        - receiver: "null"
          matchers: [ 'alertname = "InfoInhibitor"' ]
    receivers:
      - name: "null"
      - name: slack
        slack_configs:
          - api_url: "https://hooks.slack.com/services/REPLACE/ME/PLEASE"
            channel: "#alerts"
            send_resolved: true
            title: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
            text: >-
              {{ range .Alerts }}*{{ .Annotations.summary }}*
              {{ .Annotations.description }}
              {{ end }}
```

### 8.4 `servicemonitor.yaml`
`monitoring.coreos.com/v1` `ServiceMonitor`, name `hello-app`, namespace `app`,
`selector.matchLabels: {app: hello-app}`, `endpoints: [{port: http, path: /metrics, interval: 15s}]`.

### 8.5 `prometheusrule.yaml`
`PrometheusRule` `hello-app-alerts` in namespace `monitoring`, group `hello-app`:

| Alert | Expression | for | severity | summary |
|---|---|---|---|---|
| `HelloAppDown` | `sum(up{namespace="app", service="hello-app"}) == 0 or absent(up{namespace="app", service="hello-app"})` | 1m | critical | No hello-app pod is being scraped |
| `HelloAppHighErrorRate` | `sum(rate(http_requests_total{namespace="app", status_code=~"5.."}[2m])) / sum(rate(http_requests_total{namespace="app"}[2m])) > 0.05` | 1m | critical | More than 5% of requests are failing |
| `HelloAppHighLatencyP95` | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="app"}[5m]))) > 0.5` | 5m | warning | p95 latency above 500 ms |
| `HelloAppPodRestarting` | `increase(kube_pod_container_status_restarts_total{namespace="app"}[10m]) > 2` | 0m | warning | A hello-app container restarted more than twice in 10 min |

Each alert has `annotations.summary` and `annotations.description` (include `{{ $value }}` where useful).

### 8.6 `grafana-dashboard.yaml`
A `ConfigMap` in namespace `monitoring` with label `grafana_dashboard: "1"`, key `hello-app.json`,
containing a dashboard titled **"hello-app: Golden Signals"** with these panels:

| Panel | PromQL |
|---|---|
| Requests per second | `sum(rate(http_requests_total{namespace="app"}[1m]))` |
| Error rate % | `100 * sum(rate(http_requests_total{namespace="app",status_code=~"5.."}[1m])) / clamp_min(sum(rate(http_requests_total{namespace="app"}[1m])), 1e-9)` |
| p50 / p95 / p99 latency | `histogram_quantile(0.5\|0.95\|0.99, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="app"}[5m])))` |
| Requests by route & status | `sum by (route, status_code) (rate(http_requests_total{namespace="app"}[1m]))` |
| Running pods | `sum(kube_pod_status_ready{namespace="app", condition="true"})` |
| Pod restarts | `sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="app"}[15m]))` |
| CPU by pod | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="app", container="hello-app"}[2m]))` |
| Memory by pod | `sum by (pod) (container_memory_working_set_bytes{namespace="app", container="hello-app"})` |

Use the default Prometheus datasource (`"datasource": {"type": "prometheus", "uid": "prometheus"}`;
check the chart's provisioned datasource uid and match it). Refresh `10s`, time range `last 30m`.

### 8.7 `monitoring/README.md`
Short: pinned chart version, install command for kind and for EKS, how to open Grafana / Prometheus /
Alertmanager, how to read the Grafana password, uninstall command.

Install command (kind):
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --version <PINNED> \
  -f monitoring/values.yaml -f monitoring/values-kind.yaml \
  -f monitoring/alertmanager-slack.values.yaml          # omit this line if Slack isn't set up yet
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard.yaml
```
EKS: the same, without `values-kind.yaml`.

### 8.8 Verify (Phase 3): on kind
```bash
kubectl -n monitoring get pods                                   # all Running
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090/targets → serviceMonitor/app/hello-app/0 shows 2/2 UP
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# Open http://localhost:3000 → dashboard "hello-app: Golden Signals" exists and shows data while scripts/traffic.sh runs
./scripts/traffic.sh errors      # within ~3 min HelloAppHighErrorRate is FIRING at http://localhost:9090/alerts
```

---

## 9. Phase 4: Jenkins (`jenkins/` + `Jenkinsfile`)

### 9.1 `jenkins/Dockerfile`
- `FROM jenkins/jenkins:lts-jdk21`, `USER root`.
- Install, detecting architecture with `dpkg --print-architecture` / `uname -m` (the Mac is arm64):
  - Docker CLI + buildx plugin from Docker's official apt repo (`docker-ce-cli`, `docker-buildx-plugin`). **Not** the daemon.
  - AWS CLI v2 (`awscli-exe-linux-aarch64.zip` on arm64, `awscli-exe-linux-x86_64.zip` on amd64).
  - `kubectl` (latest stable from `dl.k8s.io`, matching arch).
  - `curl`, `unzip`, `git`.
- `COPY plugins.txt` then `RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt`.
- Stay `USER root` (comment: so the container can use the host's Docker socket without group-id juggling;
  acceptable **only** because this Jenkins runs locally on a laptop and is never exposed to the internet).

### 9.2 `jenkins/plugins.txt`
```
workflow-aggregator
git
credentials-binding
pipeline-stage-view
timestamper
ws-cleanup
```

### 9.3 `jenkins/docker-compose.yml`
```yaml
services:
  jenkins:
    build: .
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"                 # Jenkins UI → http://localhost:8080
    volumes:
      - jenkins_home:/var/jenkins_home          # jobs, credentials, history survive restarts
      - /var/run/docker.sock:/var/run/docker.sock   # lets Jenkins run `docker build` using the Mac's Docker
    restart: unless-stopped
volumes:
  jenkins_home:
```

### 9.4 Jenkins configuration the owner does by hand (document in RUNBOOK; agent does NOT automate)
- **Global environment variables** (Manage Jenkins → System → Global properties):
  `AWS_REGION=ap-south-1`, `CLUSTER_NAME=eks-pipeline-dev`, `ECR_REPO_URL=<terraform output>`, `DEPLOY_ENABLED=false|true`.
- **Credentials** (Manage Jenkins → Credentials → System → Global), kind *Secret text*:
  `aws-access-key-id`, `aws-secret-access-key` (values from `terraform output`).
- **Job**: Pipeline job `hello-app`, "Pipeline script from SCM" → Git → repo URL → branch `*/main` → Script Path `Jenkinsfile`.

### 9.5 `Jenkinsfile` (declarative). Required behaviour
```groovy
pipeline {
  agent any
  options {
    timestamps()
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds()                    // two deploys at once would fight each other
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  triggers { pollSCM('H/2 * * * *') }            // local Jenkins can't receive GitHub webhooks, so it polls every ~2 min
  environment {
    APP_DIR = 'app'
    NAMESPACE = 'app'
    DEPLOYMENT = 'hello-app'
    KUBECONFIG = "${WORKSPACE}/.kube/config"     // per-build kubeconfig, deleted in post
  }
  stages {
    stage('Preflight')   { /* fail fast with a clear message if AWS_REGION, CLUSTER_NAME, ECR_REPO_URL are unset
                             (only when DEPLOY_ENABLED == 'true'); set env.IMAGE_TAG = short git SHA (7 chars) */ }
    stage('Test')        { /* docker build --target test -t hello-app:test-${IMAGE_TAG} app */ }
    stage('Build')       { /* docker build --target runtime --build-arg APP_VERSION=${IMAGE_TAG} -t ${ECR_REPO_URL}:${IMAGE_TAG} app
                             (if DEPLOY_ENABLED != 'true', tag as hello-app:${IMAGE_TAG} instead) */ }
    stage('Push to ECR') { /* when DEPLOY_ENABLED == 'true'. withCredentials(string x2) → AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
                             Registry host = ECR_REPO_URL before the first '/'.
                             If `aws ecr describe-images --repository-name hello-app --image-ids imageTag=${IMAGE_TAG}` succeeds,
                             SKIP the push (tags are IMMUTABLE, so re-running the same commit would otherwise fail).
                             Else: aws ecr get-login-password | docker login --username AWS --password-stdin <host>; docker push. */ }
    stage('Deploy to EKS') { /* when DEPLOY_ENABLED == 'true'. withCredentials as above.
                             aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --kubeconfig $KUBECONFIG
                             sed "s|IMAGE_PLACEHOLDER|${ECR_REPO_URL}:${IMAGE_TAG}|" k8s/deployment.yaml | kubectl apply -f -
                             kubectl apply -f k8s/service.yaml
                             kubectl -n app annotate deploy/hello-app kubernetes.io/change-cause="jenkins #${BUILD_NUMBER} ${IMAGE_TAG}" --overwrite
                             if ! kubectl -n app rollout status deploy/hello-app --timeout=120s; then
                               echo "Rollout failed → rolling back"; kubectl -n app rollout undo deploy/hello-app
                               kubectl -n app rollout status deploy/hello-app --timeout=120s; exit 1
                             fi */ }
  }
  post {
    always  { /* docker logout <host> || true; rm -rf .kube; docker image rm hello-app:test-${IMAGE_TAG} || true; cleanWs() */ }
    success { echo "Deployed ${IMAGE_TAG}" }
    failure { echo "Pipeline failed. If the deploy stage failed, the previous version was restored." }
  }
}
```
Notes for the agent:
- Use `sh '''...'''` blocks with `set -euo pipefail` at the top.
- Never `echo` secrets. Use single-quoted Groovy strings for shell code that references credentials, so Groovy
  doesn't interpolate secrets (Jenkins warns about this).
- The first deploy also works with this logic (`kubectl apply` creates the Deployment).

### 9.6 Verify (Phase 4): local, free
```bash
cd jenkins && docker compose up -d --build
docker exec jenkins docker version && docker exec jenkins aws --version && docker exec jenkins kubectl version --client
# In the UI with DEPLOY_ENABLED=false: Build Now → Preflight, Test, Build stages green; Push/Deploy skipped.
# Break a test on purpose → Test stage red, nothing else runs. Revert.
```

---

## 10. Phase 5: Terraform (`infra/`)

General rules:
- Every `.tf` directory has `versions.tf` with `required_version = ">= 1.10"` and `aws ~> 6.0`.
- Provider block (in `bootstrap` and `envs/dev`):
  ```hcl
  provider "aws" {
    region = var.region
    default_tags { tags = { Project = "eks-delivery-pipeline", Environment = "dev", ManagedBy = "terraform", Owner = var.owner } }
  }
  ```
- Run `terraform fmt -recursive` and `terraform validate` (with `init -backend=false`) before finishing.
- Commit `.terraform.lock.hcl` files.

### 10.1 `infra/bootstrap/` (local state, run once)
- `data "aws_caller_identity" "current" {}`.
- `aws_s3_bucket` named `eks-pipeline-tfstate-${account_id}`, `force_destroy = true`.
- `aws_s3_bucket_versioning` enabled (so a bad state write can be recovered).
- `aws_s3_bucket_server_side_encryption_configuration` with `AES256`.
- `aws_s3_bucket_public_access_block` with all four flags `true`.
- Output `state_bucket_name`.
- Comment: this folder keeps its own state **locally** (chicken-and-egg: the bucket can't store the state of its own creation).
  No DynamoDB table, because Terraform ≥ 1.10 locks state with a lock file in S3 (`use_lockfile = true`).
  Mention in a comment that DynamoDB locking is the older approach.

### 10.2 `modules/network/`
Inputs: `name`, `vpc_cidr` (default `10.0.0.0/16`), `cluster_name`.
- `data "aws_availability_zones" "available" { state = "available" }`, use the first 2.
- `aws_vpc`: `enable_dns_support = true`, `enable_dns_hostnames = true` (EKS nodes need DNS hostnames).
- 2 × `aws_subnet` (public), `cidrsubnet(var.vpc_cidr, 4, i)` → `/20`s, `map_public_ip_on_launch = true`,
  tags `kubernetes.io/role/elb = "1"` and `kubernetes.io/cluster/${cluster_name} = "shared"`.
- `aws_internet_gateway`, one `aws_route_table` with `0.0.0.0/0 → igw`, 2 associations.
- Outputs: `vpc_id`, `public_subnet_ids`.
- Big comment: **why public subnets / no NAT**: cost. Nodes get public IPs but the EKS-managed security
  group only allows traffic from inside the cluster. In production you'd use private subnets + NAT or VPC endpoints.

### 10.3 `modules/eks/`
Inputs: `cluster_name`, `kubernetes_version`, `subnet_ids`, `public_access_cidrs` (default `["0.0.0.0/0"]`),
`node_instance_types` (default `["t4g.medium", "t4g.large"]`), `capacity_type` (default `"SPOT"`),
`desired_size` (2), `min_size` (1), `max_size` (2).
- **Cluster IAM role**: trust `eks.amazonaws.com`, attach `arn:aws:iam::aws:policy/AmazonEKSClusterPolicy`.
- **`aws_eks_cluster`**:
  ```hcl
  version = var.kubernetes_version
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs   # set to your own IP/32 in tfvars for safety
  }
  access_config {
    authentication_mode                         = "API"   # modern access entries, no aws-auth ConfigMap
    bootstrap_cluster_creator_admin_permissions = true    # whoever runs terraform gets cluster-admin
  }
  upgrade_policy { support_type = "STANDARD" }            # never pay extended-support pricing
  # enabled_cluster_log_types intentionally omitted → no CloudWatch cost
  # encryption_config intentionally omitted → no KMS key cost
  ```
  `depends_on` the policy attachment.
- **Node IAM role**: trust `ec2.amazonaws.com`, attach `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryPullOnly` (pull-only is tighter than ReadOnly; comment why).
- **`aws_eks_node_group`**: `ami_type = "AL2023_ARM_64_STANDARD"`, `capacity_type = var.capacity_type`,
  `instance_types = var.node_instance_types`, `disk_size = 20`, scaling config from inputs,
  `update_config { max_unavailable = 1 }`, `depends_on` all three attachments. Comment: why not `t4g.small`
  (too little memory for the monitoring stack), and why not `m6g.medium` (only 8 pods per node because of ENI limits).
- Outputs: `cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_version`.

### 10.4 `modules/ecr/`
- `aws_ecr_repository` `hello-app`: `image_tag_mutability = "IMMUTABLE"` (a tag always means the same image,
  which is what makes rollbacks trustworthy), `image_scanning_configuration { scan_on_push = true }` (basic scanning is free),
  `force_delete = true`.
- `aws_ecr_lifecycle_policy`: expire images beyond the newest 5.
- Outputs: `repository_url`, `repository_arn`, `repository_name`.

### 10.5 `modules/ci-access/` (least-privilege Jenkins identity)
Inputs: `user_name` (default `jenkins-ci`), `ecr_repository_arn`, `cluster_name`, `cluster_arn`, `app_namespace` (`app`).
- `aws_iam_user` `jenkins-ci`.
- `aws_iam_user_policy` (inline) with exactly:
  - `ecr:GetAuthorizationToken` on `*` (AWS requires `*` for this one action; comment it).
  - `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`,
    `ecr:PutImage`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, `ecr:DescribeImages` on the repo ARN only.
  - `eks:DescribeCluster` on the cluster ARN only.
- `aws_iam_access_key` for the user. Comment the trade-off honestly: the secret ends up in Terraform state
  (encrypted in S3). Acceptable for a short-lived demo because `terraform destroy` deletes the key. In production
  Jenkins would run on AWS and use an IAM role (instance profile / IRSA / OIDC) with no long-lived keys.
- `aws_eks_access_entry` for the user ARN (`type = "STANDARD"`).
- `aws_eks_access_policy_association`: `policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"`,
  `access_scope { type = "namespace", namespaces = [var.app_namespace] }`. So Jenkins can change Deployments in
  `app` and nothing else.
- Outputs: `access_key_id`, `secret_access_key` (**`sensitive = true`**).

### 10.6 `envs/dev/`
- `versions.tf` includes `backend "s3" {}` (empty, configured via `-backend-config=backend.hcl`).
- `backend.hcl.example`:
  ```hcl
  bucket       = "eks-pipeline-tfstate-<ACCOUNT_ID>"   # from: terraform -chdir=infra/bootstrap output state_bucket_name
  key          = "dev/terraform.tfstate"
  region       = "ap-south-1"
  use_lockfile = true      # S3-native state locking (Terraform >= 1.10)
  encrypt      = true
  ```
- `variables.tf`: `region` (default `ap-south-1`), `owner`, `cluster_name` (default `eks-pipeline-dev`),
  `kubernetes_version` (**no default**, so the owner must consciously choose a standard-support version),
  `public_access_cidrs`, `capacity_type`, `node_instance_types`.
- `terraform.tfvars.example`:
  ```hcl
  owner               = "your-name"
  kubernetes_version  = "1.XX"                 # newest STANDARD_SUPPORT version, see docs/RUNBOOK.md
  public_access_cidrs = ["203.0.113.10/32"]    # your public IP: curl -s https://checkip.amazonaws.com
  # capacity_type     = "ON_DEMAND"            # only if Spot capacity is unavailable
  ```
- `main.tf`: call `network` → `eks` → `ecr` → `ci-access`.
- `outputs.tf`: `region`, `cluster_name`, `ecr_repository_url`, `jenkins_access_key_id`,
  `jenkins_secret_access_key` (sensitive), and `configure_kubectl = "aws eks update-kubeconfig --region ... --name ..."`.

### 10.7 Verify (Phase 5): free, nothing is created
```bash
terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/envs/dev init -backend=false && terraform -chdir=infra/envs/dev validate
terraform fmt -check -recursive infra
grep -rE 'aws_nat_gateway|aws_lb|aws_cloudwatch_log_group|aws_kms_key|aws_instance|aws_eip|terraform-aws-modules' infra && echo "FORBIDDEN RESOURCE FOUND" || echo "clean"
```
(The owner later runs `terraform plan` with real credentials. `plan` creates nothing and is free.)

---

## 11. Phase 6: Helper scripts (`scripts/`)

All scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, a header comment saying what it does, `chmod +x`.

| Script | Behaviour |
|---|---|
| `kind-up.sh` | Fail with an install hint if `kind`/`kubectl` missing. Create cluster `devops-lab` from `kind/kind-config.yaml` if it doesn't exist. `kubectl create namespace app` (ignore if exists). |
| `kind-deploy.sh` | `docker build --target runtime --build-arg APP_VERSION=local-$(git rev-parse --short HEAD 2>/dev/null \|\| echo dev) -t hello-app:local app`, `kind load docker-image hello-app:local --name devops-lab`, apply `k8s/` with `sed` replacing `IMAGE_PLACEHOLDER` → `hello-app:local`, then `kubectl -n app rollout restart` + `rollout status`. Uses the `kind-devops-lab` kube context explicitly (`--context`) so it can never touch EKS. |
| `kind-down.sh` | `kind delete cluster --name devops-lab`. |
| `traffic.sh` | Usage `traffic.sh [normal\|errors\|slow]`. Runs a temporary pod **inside the cluster**: `kubectl -n app run traffic --image=curlimages/curl --rm -it --restart=Never -- sh -c '<loop>'`, calling `http://hello-app` (the Service) every 0.2 s until Ctrl-C. `normal` hits `/` and prints `<status> <version> <pod>` per line (so you can watch versions switch during a rollout); `errors` makes ~30% of calls to `/error`; `slow` hits `/slow?ms=800`. Why in-cluster: `kubectl port-forward` sticks to ONE pod and breaks when that pod is replaced, so it can't prove zero downtime; going through the Service can. |
| `teardown-check.sh` | Read-only. For `${AWS_REGION:-ap-south-1}` print anything still alive and billable: EKS clusters, EC2 instances (not terminated), NAT gateways, load balancers (`elbv2` + classic), Elastic IPs, EBS volumes, ECR repos, S3 buckets starting with `eks-pipeline-tfstate`, and `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=eks-delivery-pipeline`. End with `ALL CLEAR` or `⚠ LEFTOVERS FOUND` and exit code 0/1. |

---

## 12. Phase 7: Documentation polish

- `README.md` already exists. Update: pinned versions table, repo layout if changed, screenshot links once the owner adds them.
- `monitoring/README.md` as in §8.7.
- Do not rewrite `docs/RUNBOOK.md`, `docs/BEGINNER_GUIDE.md`, `docs/INTERVIEW_PREP.md` unless something in them
  became wrong because of an implementation detail. If so, fix only that part.

## 13. Definition of done

- [ ] `npm test` passes; `docker build --target test` passes; runtime image is arm64, runs as non-root.
- [ ] App deploys to kind with `scripts/kind-deploy.sh`; 2/2 pods Ready; `kubectl rollout restart` causes no non-200 lines while `scripts/traffic.sh normal` runs.
- [ ] Demo 3 check on kind: uncomment the DEMO 3 block, `kind-deploy.sh` → new pods CrashLoopBackOff while the old pods keep serving. Re-comment it.
- [ ] Monitoring installs on kind; Prometheus target UP; Grafana dashboard shows data; `HelloAppHighErrorRate` fires with `traffic.sh errors`.
- [ ] Local Jenkins builds; pipeline with `DEPLOY_ENABLED=false` runs Test + Build green; a failing test stops the pipeline.
- [ ] `terraform validate` + `fmt -check` pass for bootstrap and dev; forbidden-resource grep is clean.
- [ ] No secrets in git (`git grep -nE 'AKIA|hooks.slack.com/services/[A-Z0-9]'` finds nothing except the placeholder).
- [ ] Every file has beginner-friendly *why* comments.
- [ ] The human then follows `docs/RUNBOOK.md` Part C for the paid EKS session.

## 14. Appendix: why each design decision was made

| Decision | Reason (use these in the interview) |
|---|---|
| Image tag = git SHA, ECR tags immutable | Every running image traces to an exact commit; a tag can never silently change, so rollbacks are trustworthy |
| Tests inside Docker (`--target test`) | Jenkins needs no Node.js installed; tests run in the same environment as production |
| `maxUnavailable: 0`, readiness probe, preStop sleep, graceful SIGTERM | The four pieces that together make rolling updates zero-downtime |
| `kubectl rollout status` + `rollout undo` | Pipeline-level automatic rollback when the new version never becomes Ready |
| Separate liveness and readiness | Liveness restarts a stuck process; readiness only removes a pod from traffic. Mixing them causes restart storms |
| EKS access entries + namespace-scoped Edit policy | Least privilege inside Kubernetes, mapped from IAM, with no `aws-auth` ConfigMap to break |
| Namespace created by admin, not Jenkins | Jenkins can't create cluster-wide objects, which limits the blast radius if its key leaks |
| S3 backend with native lockfile | Shared, versioned, encrypted state; prevents two `apply`s at once |
| Spot + Graviton + no NAT/LB | Cuts the bill to roughly the EKS control-plane fee; it's a FinOps decision you can explain |
| Prometheus pull model + ServiceMonitor | Targets are discovered from Kubernetes labels; no manual config per pod |
| Alert on symptoms (error rate, latency, down) | Pages a human only when users are affected, the same idea as the SLOs from the OZi internship |
