# ADR 0007: Plain Kubernetes YAML for the app instead of a Helm chart

**Status:** Accepted

## Context
There is one app, one environment, and two manifests. The goal includes being able to read and explain every line.

## Decision
The app uses plain YAML in `k8s/`, and the only templating is `sed` replacing `IMAGE_PLACEHOLDER`. Helm is used
only to install the third-party monitoring stack (kube-prometheus-stack), where a maintained chart saves a lot of work.

## Consequences
- Every field the cluster receives is visible in the repository, with no template logic to trace.
- Adding environments would mean duplicating files, which doesn't scale beyond one or two.

## In production
Kustomize overlays (base + dev/staging/prod) or a Helm chart with per-environment values, rendered and applied
by a GitOps tool.

Implemented in [`k8s/`](../../k8s/) and [`scripts/kind-deploy.sh`](../../scripts/kind-deploy.sh).
