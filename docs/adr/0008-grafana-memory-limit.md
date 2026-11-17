# ADR 0008: Grafana memory limit raised from 256Mi to 1Gi after measuring

**Status:** Accepted

## Context
The original spec set Grafana's memory limit to 256Mi to keep the monitoring stack small. On the first install
with kube-prometheus-stack 93.3.0 (which ships Grafana 13), the Helm release ended up `failed`: the `grafana`
container had been **OOMKilled 30 times** and never became Ready.

## Investigation
1. `kubectl get pods`: Grafana pod `2/3 Running`, status `OOMKilled`.
2. Checked each container's last state: only the `grafana` container was killed (exit 137); the sidecars were fine.
3. Logs showed a normal startup (migrations, plugin registration), with no crash loop caused by bad config.
4. Raised the limit temporarily on kind and measured with Prometheus:
   `container_memory_working_set_bytes{container="grafana"}` → **~703 MiB, steady**, not a startup spike.

## Decision
Set `grafana.resources.limits.memory` to **1Gi** (request unchanged). The reason is recorded in a comment in
`monitoring/values.yaml`. Pinning an older Grafana image was rejected as a larger deviation from the chart's tested set.

## Consequences
- Grafana runs reliably. Cost is unchanged: the nodes are a fixed size, and the stack still fits on 2 × t4g.medium.
- The memory request (128Mi) is well below actual usage, so the scheduler under-counts Grafana.

## In production
Set requests close to measured usage (e.g. 768Mi request / 1Gi limit), and re-measure whenever the chart is upgraded.

Implemented in [`monitoring/values.yaml`](../../monitoring/values.yaml).
