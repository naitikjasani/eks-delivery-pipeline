#!/usr/bin/env bash
# kind-up.sh: create the free local Kubernetes cluster "devops-lab" and the "app" namespace.
# Safe to run more than once: it skips anything that already exists.
#
# Usage: ./scripts/kind-up.sh

# -e: stop at the first failing command. -u: treat unset variables as errors.
# -o pipefail: a pipeline fails if ANY command in it fails, not just the last one.
set -euo pipefail

CLUSTER_NAME="devops-lab"
# kind names the kubectl context "kind-<cluster name>". We always pass it explicitly,
# so this script can never touch your EKS cluster by accident.
CONTEXT="kind-${CLUSTER_NAME}"

# Run from the repository root, no matter where the script is called from, so relative paths work.
cd "$(dirname "$0")/.."

# Fail early with a helpful hint instead of a confusing "command not found" halfway through.
for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      docker)  echo "ERROR: docker not found. Install and start Docker Desktop." >&2 ;;
      kind)    echo "ERROR: kind not found. Install it with: brew install kind" >&2 ;;
      kubectl) echo "ERROR: kubectl not found. Install it with: brew install kubectl" >&2 ;;
    esac
    exit 1
  fi
done

# kind runs the cluster nodes as Docker containers, so Docker must actually be running.
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running. Start Docker Desktop and try again." >&2
  exit 1
fi

# Create the cluster only if it doesn't exist yet (grep -x matches the whole line exactly).
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists, skipping creation."
else
  echo "Creating kind cluster '$CLUSTER_NAME' (takes about a minute)..."
  kind create cluster --name "$CLUSTER_NAME" --config kind/kind-config.yaml
fi

# The app namespace is created by the admin (you), not by the deploy pipeline, just like on EKS.
if kubectl --context "$CONTEXT" get namespace app >/dev/null 2>&1; then
  echo "Namespace 'app' already exists."
else
  kubectl --context "$CONTEXT" create namespace app
fi

kubectl --context "$CONTEXT" get nodes
echo "Done. Next: ./scripts/kind-deploy.sh"
