# Run the demo yourself (about 10 minutes, free)

Everything here runs on a local [kind](https://kind.sigs.k8s.io/) cluster in Docker. No AWS account is needed.

## Prerequisites
Docker Desktop (6 GB+ memory), `kind`, `kubectl`, `helm` and `make`. On macOS:
```bash
brew install kind kubectl helm
```

## One command
```bash
git clone https://github.com/naitikjasani/eks-delivery-pipeline.git && cd eks-delivery-pipeline
make demo
```
`make demo` creates the cluster, builds and deploys the app, and installs Prometheus, Grafana and Alertmanager
if they're missing. Then it walks through four acts, pausing between them:

| Act | What you see | What it proves |
|---|---|---|
| 1 · The app | Pods, the Service answering from different pods, the Prometheus metrics | The app runs on Kubernetes and is observable |
| 2 · Zero-downtime rollout | A live counter of requests during `kubectl rollout restart`, ending in "N/N requests returned HTTP 200" | Rolling updates never drop a request |
| 3 · Broken release | A release that passes its tests but crashes on startup; the rollout times out; `kubectl rollout undo`; traffic stayed 200 | Automatic rollback, the same logic as the Jenkins pipeline |
| 4 · Alerting | ~30% error traffic, then HelloAppHighErrorRate goes inactive → pending → **firing** | Symptom-based alerting works end to end |

Run a single act with `make demo ACT=rollout` (or `app`, `rollback`, `alert`). Set `FAST=1` to skip the pauses.

![Zero-downtime rollout](media/zero-downtime.gif)

## Look around while it runs
| UI | URL | Login |
|---|---|---|
| Grafana: "hello-app: Golden Signals" dashboard | http://localhost:3000 | `admin` / `kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` |
| Prometheus: targets and alerts | http://localhost:9090/alerts | none |

(The demo starts these port-forwards and stops them when it finishes.)

## Safety
The demo script uses a kubeconfig that contains **only** the kind cluster, so it can't touch any cloud cluster,
even if your normal kubectl context points at one. It never modifies files in the repository: the broken release is
built from a temporary copy of the app.

## Clean up
```bash
make down        # deletes the kind cluster
```
