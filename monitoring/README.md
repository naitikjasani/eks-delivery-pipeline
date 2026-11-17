# Monitoring: Prometheus, Grafana and Alertmanager

Everything here installs with one Helm chart, **kube-prometheus-stack**, plus three small YAML files of our own.
The same files work on the local kind cluster and on EKS.

| Pinned version | |
|---|---|
| Chart | `prometheus-community/kube-prometheus-stack` **93.3.0** (app version v0.95.2, Grafana 13.3) |

The version is pinned so that every install gets exactly the same components. Before upgrading it,
check the newest version with `helm search repo prometheus-community/kube-prometheus-stack`.

## What each file does

| File | Purpose |
|---|---|
| `values.yaml` | Our chart settings for kind and EKS: small resource requests, 6 h retention, no disks, EKS-hidden components off |
| `values-kind.yaml` | kind only: turns off node-exporter's host root mount, which Docker Desktop doesn't support |
| `alertmanager-slack.values.example.yaml` | Template for Slack alerts. Copy it to `alertmanager-slack.values.yaml` (gitignored) and paste your webhook in |
| `servicemonitor.yaml` | Tells Prometheus to scrape `/metrics` on the `hello-app` Service |
| `prometheusrule.yaml` | 4 alerts: app down, error rate > 5%, p95 latency > 500 ms, restart loop |
| `grafana-dashboard.yaml` | The "hello-app: Golden Signals" dashboard, loaded automatically by Grafana's sidecar |

## Install

Run these from the repository root. **Check your kubectl context first** (`kubectl config current-context`).

**kind (free, local):**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --version 93.3.0 \
  -f monitoring/values.yaml -f monitoring/values-kind.yaml \
  -f monitoring/alertmanager-slack.values.yaml          # omit this line if Slack isn't set up yet
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard.yaml
```

**EKS:** the same, **without** `-f monitoring/values-kind.yaml`:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --version 93.3.0 \
  -f monitoring/values.yaml \
  -f monitoring/alertmanager-slack.values.yaml          # omit this line if Slack isn't set up yet
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard.yaml
```

The first install takes a few minutes while the images download. Wait until everything is Running:
```bash
kubectl -n monitoring get pods
```
`kubectl apply` must come after `helm`, because `ServiceMonitor` and `PrometheusRule` are custom resource
types that the chart installs. Deploy the app first (or later), because the ServiceMonitor lives in namespace `app`.

## Open the UIs

Each command blocks the terminal while it runs. Use a separate terminal for each one, and Ctrl-C to stop.

| UI | Command | Open |
|---|---|---|
| Grafana | `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80` | http://localhost:3000 (user `admin`) |
| Prometheus | `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090` | http://localhost:9090 (Status → Targets, Alerts) |
| Alertmanager | `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093` | http://localhost:9093 |

**Grafana password.** The chart generates a random one and stores it in a Kubernetes Secret. No password is
written in git:
```bash
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
Then go to Dashboards → **hello-app: Golden Signals**.

## Check that it works

1. Prometheus → Status → Targets: `serviceMonitor/app/hello-app/0` shows **2/2 UP**.
2. Run `./scripts/traffic.sh normal` → the Grafana dashboard shows requests per second.
3. Run `./scripts/traffic.sh errors` → within ~3 minutes, Prometheus → Alerts shows **HelloAppHighErrorRate**
   as FIRING (and Slack gets a message, if configured). Stop the script; a few minutes later it resolves.

## Uninstall
```bash
kubectl delete -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard.yaml
helm -n monitoring uninstall monitoring
kubectl delete namespace monitoring
```
Helm does not delete the chart's CRDs (the custom resource types). That's harmless on EKS, because the
cluster is destroyed anyway. On kind, `./scripts/kind-down.sh` removes everything.

## Notes
- **Grafana memory limit is 1Gi**, not 256Mi. The Grafana 13 image in chart 93.x uses ~700Mi once it has
  started (measured on kind). With 256Mi it was OOM-killed in a loop.
- **No persistent storage.** Prometheus keeps 6 hours of data in memory (an `emptyDir`), and Grafana has no disk.
  A pod restart loses the history, which is fine for a demo and avoids EBS volumes (and their cost).
- **Watchdog** is an alert that fires all the time on purpose (a "dead man's switch": if it stops, the alerting
  pipeline is broken). The Slack config routes it to a `null` receiver, so it never spams the channel.
