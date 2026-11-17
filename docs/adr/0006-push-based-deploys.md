# ADR 0006: Push-based deploys from Jenkins instead of GitOps

**Status:** Accepted

## Context
Deployments can be *pushed* by CI (`kubectl apply` from the pipeline) or *pulled* by an in-cluster GitOps agent
(ArgoCD/Flux) that keeps the cluster in sync with Git. The project needs one environment, a short-lived cluster,
and a visible, explainable automatic rollback.

## Decision
Jenkins deploys with `kubectl apply`, waits on `kubectl rollout status --timeout=120s`, and runs
`kubectl rollout undo` if the rollout fails. The image is injected by replacing `IMAGE_PLACEHOLDER` with `sed`.

## Consequences
- The whole flow (test → build → push → deploy → verify → rollback) is visible in one pipeline log.
- Nothing extra runs in the cluster.
- The CI system holds cluster credentials (scoped to one namespace, see ADR 0003).
- Drift (someone running `kubectl edit`) isn't corrected automatically until the next deploy.

## In production
GitOps: CI builds and pushes the image, then updates a manifest repo; ArgoCD applies it, self-heals drift, and
handles rollbacks (optionally progressive delivery with Argo Rollouts). The CI system then needs no cluster
credentials at all.

Implemented in the "Deploy to EKS" stage of [`Jenkinsfile`](../../Jenkinsfile).
