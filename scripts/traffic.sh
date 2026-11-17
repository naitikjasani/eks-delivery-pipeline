#!/usr/bin/env bash
# traffic.sh: send a steady stream of requests to hello-app from INSIDE the cluster, until Ctrl-C.
#
# Usage: ./scripts/traffic.sh [normal|errors|slow]      (default: normal)
#   normal  GET /                 prints "<status> <version> <pod>" per request (watch versions switch in a rollout)
#   errors  ~30% GET /error       pushes the error rate above 5% so HelloAppHighErrorRate fires
#   slow    GET /slow?ms=800      pushes p95 latency above 500 ms (HelloAppHighLatencyP95)
#
# Why run inside the cluster? `kubectl port-forward` sticks to ONE pod and breaks when that pod is replaced,
# so it can't prove zero downtime. A temporary pod calling the Service (http://hello-app) goes through
# Kubernetes' normal load balancing, exactly like real traffic.
#
# It uses your CURRENT kubectl context, so it works on kind and on EKS. Check it with:
#   kubectl config current-context

set -euo pipefail

MODE="${1:-normal}"

# Each loop below runs inside the curlimages/curl pod (a tiny image with curl and a basic shell).
# The \$ signs are escaped so YOUR shell leaves them alone and the pod's shell expands them.
# -s: silent, -m 2: give up after 2 s, -w: append the HTTP status code (000 means no connection at all).
case "$MODE" in
  normal)
    LOOP="while true; do
      out=\$(curl -s -m 2 -w ' %{http_code}' http://hello-app/)
      code=\${out##* }
      body=\${out% *}
      version=\$(echo \"\$body\" | sed -n 's/.*\"version\":\"\\([^\"]*\\)\".*/\\1/p')
      pod=\$(echo \"\$body\" | sed -n 's/.*\"pod\":\"\\([^\"]*\\)\".*/\\1/p')
      echo \"\$code \$version \$pod\"
      sleep 0.2
    done"
    ;;
  errors)
    # 3 of every 10 requests go to /error, so the error rate is ~30%, far above the 5% alert threshold.
    LOOP="i=0; while true; do
      i=\$((i + 1))
      if [ \$((i % 10)) -lt 3 ]; then path=/error; else path=/; fi
      code=\$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://hello-app\$path)
      echo \"\$code \$path\"
      sleep 0.2
    done"
    ;;
  slow)
    LOOP="while true; do
      curl -s -m 7 -o /dev/null -w '%{http_code} /slow %{time_total}s\n' 'http://hello-app/slow?ms=800'
      sleep 0.2
    done"
    ;;
  *)
    echo "Usage: $0 [normal|errors|slow]" >&2
    exit 1
    ;;
esac

echo "Context: $(kubectl config current-context)   Mode: $MODE   (Ctrl-C to stop)"

# Remove a leftover "traffic" pod from an earlier run that was interrupted, otherwise `run` would fail.
kubectl -n app delete pod traffic --ignore-not-found --wait=true >/dev/null

# Clean up the pod when this script exits for any reason (Ctrl-C included).
trap 'kubectl -n app delete pod traffic --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT

# -i keeps the output streaming to your terminal. -t (a TTY) is added only when you run this in a real
# terminal, so the script also works when its output is piped or run from another script.
TTY_FLAGS="-i"
if [ -t 0 ]; then TTY_FLAGS="-it"; fi

# --rm deletes the pod when it stops; --restart=Never makes it a one-off pod rather than a Deployment.
kubectl -n app run traffic --image=curlimages/curl --rm $TTY_FLAGS --restart=Never --quiet -- sh -c "$LOOP"
