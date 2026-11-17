#!/usr/bin/env bash
# kind-deploy.sh: build the app image, load it into the kind cluster, and deploy k8s/ to it.
# This is the free, local version of what Jenkins' "Deploy to EKS" stage does.
#
# Usage: ./scripts/kind-deploy.sh      (run ./scripts/kind-up.sh first)

set -euo pipefail

CLUSTER_NAME="devops-lab"
# Every kubectl command below uses this context explicitly, so this script can NEVER deploy to EKS,
# even if your current kubectl context points at the EKS cluster.
CONTEXT="kind-${CLUSTER_NAME}"
IMAGE="hello-app:local"

# Run from the repository root so the relative paths (app/, k8s/) work.
cd "$(dirname "$0")/.."

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "ERROR: kind cluster '$CLUSTER_NAME' not found. Run ./scripts/kind-up.sh first." >&2
  exit 1
fi

# Version label shown by GET /, e.g. "local-a1b2c3d". Falls back to "dev" outside a git repo.
VERSION="local-$(git rev-parse --short HEAD 2>/dev/null || echo dev)"

echo "==> Building $IMAGE (APP_VERSION=$VERSION)"
docker build --target runtime --build-arg APP_VERSION="$VERSION" -t "$IMAGE" app

# kind nodes can't see the Mac's local images, and there's no registry here. `kind load` copies the
# image straight into every node, so imagePullPolicy: IfNotPresent finds it without pulling.
echo "==> Loading $IMAGE into kind cluster '$CLUSTER_NAME'"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

# Swap the literal IMAGE_PLACEHOLDER for our image and pipe the result straight into kubectl.
# The file on disk stays unchanged, so the same manifest works for EKS.
echo "==> Applying k8s/ manifests"
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|" k8s/deployment.yaml | kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" apply -f k8s/service.yaml

# The tag is always "hello-app:local", so `apply` alone sees no change in the pod spec and wouldn't
# replace the pods. A restart forces a rolling update onto the image we just loaded.
echo "==> Rolling out"
kubectl --context "$CONTEXT" -n app rollout restart deployment/hello-app
# Wait until the new pods are Ready (or fail after 120 s, the same timeout Jenkins uses).
kubectl --context "$CONTEXT" -n app rollout status deployment/hello-app --timeout=120s

kubectl --context "$CONTEXT" -n app get pods -o wide
echo "Done. Try: kubectl -n app port-forward svc/hello-app 8081:80   then open http://localhost:8081"
