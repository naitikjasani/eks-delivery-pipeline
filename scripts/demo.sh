#!/usr/bin/env bash
# demo.sh: a guided live demo of the whole project on the free local kind cluster.
#
# Usage:  ./scripts/demo.sh [all|app|rollout|rollback|alert]      (default: all)
#   app       Act 1: the running app, its pods, and its metrics
#   rollout   Act 2: zero-downtime rolling update under live traffic
#   rollback  Act 3: a broken release is contained and rolled back automatically
#   alert     Act 4: error traffic makes the HelloAppHighErrorRate alert fire
#
# Environment:
#   FAST=1                 no "press Enter" pauses (for recordings)
#   ROLLOUT_TIMEOUT=45s    how long Act 3 waits before rolling back (Jenkins uses 120s; shorter keeps a demo moving)
#
# Safety: every kubectl command runs against a kubeconfig that contains ONLY the kind cluster,
# so this script cannot touch EKS even if your normal kubectl context points there. It never modifies the repo.

set -euo pipefail

ACT="${1:-all}"
FAST="${FAST:-0}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-45s}"
CLUSTER="devops-lab"

# Run from the repository root so relative paths work.
cd "$(dirname "$0")/.."

# ---------- helpers ----------
WORK="$(mktemp -d)"                               # scratch space: kubeconfig, traffic logs, temp app copy
TRAFFIC_PID=""                                    # background traffic generator, if running
PF_PIDS=()                                        # port-forwards this script started

banner() { printf '\n\033[1;36m━━━━ %s ━━━━\033[0m\n' "$1"; }
say()    { printf '\033[0;37m%s\033[0m\n' "$1"; }
ok()     { printf '\033[1;32m✔ %s\033[0m\n' "$1"; }
warn()   { printf '\033[1;31m✘ %s\033[0m\n' "$1"; }
# Print a command in yellow, then run it, so the audience sees exactly what's happening.
run()    { printf '\033[1;33m$ %s\033[0m\n' "$*"; "$@"; }
pause()  { if [ "$FAST" != "1" ]; then read -r -p $'\n\033[2m▶ press Enter: '"$1"$'\033[0m ' _; fi; }

stop_traffic() {
  if [ -n "$TRAFFIC_PID" ]; then
    kill "$TRAFFIC_PID" 2>/dev/null || true
    wait "$TRAFFIC_PID" 2>/dev/null || true
    TRAFFIC_PID=""
  fi
  # The traffic pod's shell loop ignores SIGTERM, so a normal delete waits out the 30 s grace period.
  # A 1-second grace period removes it quickly, so the next act can start its own traffic pod straight away.
  kubectl -n app delete pod traffic --ignore-not-found --grace-period=1 --wait=true >/dev/null 2>&1 || true
}

cleanup() {
  stop_traffic
  for pid in "${PF_PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# Start scripts/traffic.sh in the background, writing one line per request to a log file.
start_traffic() {   # $1 = mode, $2 = log file
  ./scripts/traffic.sh "$1" > "$2" 2>&1 &
  TRAFFIC_PID=$!
  # Wait until requests are flowing (the traffic pod needs a few seconds to start).
  for _ in $(seq 1 60); do grep -qE '^[0-9]{3} ' "$2" 2>/dev/null && return 0; sleep 1; done
  warn "traffic generator did not start"; tail -5 "$2" >&2; exit 1
}

# Count lines like "200 local-abc hello-app-xyz" in a traffic log.
count_total() { grep -cE '^[0-9]{3} ' "$1" || true; }
count_bad()   { grep -E '^[0-9]{3} ' "$1" | grep -cv '^200 ' || true; }

# Start a port-forward in the background unless something already listens on that local port.
port_forward() {    # $1 = service, $2 = local:remote
  local lport="${2%%:*}"
  if nc -z localhost "$lport" 2>/dev/null; then return 0; fi
  kubectl -n monitoring port-forward "svc/$1" "$2" >/dev/null 2>&1 &
  PF_PIDS+=($!)
  # disown: the cleanup trap stops it later; this keeps bash from printing a "Terminated" job notice when it does.
  disown "$!"
  for _ in $(seq 1 20); do nc -z localhost "$lport" 2>/dev/null && return 0; sleep 0.5; done
}

# ---------- preflight ----------
preflight() {
  banner "Preflight"
  docker info >/dev/null 2>&1 || { warn "Docker is not running. Start Docker Desktop first."; exit 1; }

  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    say "No kind cluster yet: creating it."
    ./scripts/kind-up.sh
  fi

  # A kubeconfig that knows ONLY the kind cluster. Exported, so traffic.sh and every kubectl below use it.
  kind get kubeconfig --name "$CLUSTER" > "$WORK/kubeconfig"
  export KUBECONFIG="$WORK/kubeconfig"

  if ! kubectl -n app get deploy hello-app >/dev/null 2>&1; then
    say "App not deployed yet: deploying it."
    ./scripts/kind-deploy.sh
  fi
  kubectl -n app rollout status deploy/hello-app --timeout=120s >/dev/null

  # Acts 1 and 4 need the monitoring stack.
  if [ "$ACT" = "all" ] || [ "$ACT" = "alert" ] || [ "$ACT" = "app" ]; then
    if ! helm --kube-context "kind-$CLUSTER" -n monitoring status monitoring >/dev/null 2>&1; then
      say "Monitoring not installed yet: installing it (first time takes a few minutes)."
      make monitoring
    fi
    port_forward monitoring-kube-prometheus-prometheus 9090:9090
    port_forward monitoring-grafana 3000:80
  fi
  ok "cluster '$CLUSTER' ready, app running ($(kubectl -n app get deploy hello-app -o jsonpath='{.status.readyReplicas}')/2 pods Ready)"
}

# ---------- Act 1: the app ----------
act_app() {
  banner "Act 1 · The app on Kubernetes"
  run kubectl -n app get deploy,pods,svc -o wide
  pause "call the app through its Service"
  say "Calling http://hello-app from a pod inside the cluster:"
  run kubectl -n app run probe --image=curlimages/curl --rm -i --restart=Never --quiet -- \
    sh -c 'for i in 1 2 3 4; do curl -s http://hello-app/; echo; done'
  say "Note the 'pod' field: the Service spreads requests across both pods."
  pause "show the Prometheus metrics the app exposes"
  run kubectl -n app run probe --image=curlimages/curl --rm -i --restart=Never --quiet -- \
    sh -c 'curl -s http://hello-app/metrics | grep -E "^http_request(s_total|_duration_seconds_count)" | head -6'
}

# ---------- Act 2: zero-downtime rolling update ----------
act_rollout() {
  banner "Act 2 · Zero-downtime rolling update"
  say "Sending ~5 requests/second through the Service while every pod gets replaced."
  local log="$WORK/rollout.log"
  start_traffic normal "$log"
  sleep 4
  local before; before="$(awk '/^[0-9]{3} /{print $3}' "$log" | sort -u | tr '\n' ' ')"

  run kubectl -n app rollout restart deploy/hello-app
  kubectl -n app rollout status deploy/hello-app --timeout=180s > "$WORK/status.log" 2>&1 &
  local rp=$!
  # Live ticker while the rollout runs. Pods are shown by the random suffix of their name (hello-app-<hash>-<suffix>),
  # which keeps the line short enough to redraw in place (\r) and clear the rest (\033[K).
  while kill -0 "$rp" 2>/dev/null; do
    printf '\r  requests: %-5s non-200: %-3s pods answering now: %s\033[K' \
      "$(count_total "$log")" "$(count_bad "$log")" \
      "$(tail -n 8 "$log" | awk '/^[0-9]{3} /{n=split($3,p,"-"); print p[n]}' | sort -u | tr '\n' ' ')"
    sleep 1
  done
  wait "$rp"; echo
  sleep 5    # keep traffic flowing a little after the rollout, so the new pods answer too
  stop_traffic

  local total bad after
  total="$(count_total "$log")"; bad="$(count_bad "$log")"
  after="$(tail -n 20 "$log" | awk '/^[0-9]{3} /{print $3}' | sort -u | tr '\n' ' ')"
  say "pods before: $before"
  say "pods after:  $after"
  if [ "$bad" -eq 0 ]; then
    ok "$total/$total requests returned HTTP 200 while every pod was replaced: zero downtime"
  else
    warn "$bad of $total requests failed"
  fi
  say "Why: maxUnavailable 0 + readiness probe + preStop sleep + graceful SIGTERM handling."
}

# ---------- Act 3: broken release + automatic rollback ----------
act_rollback() {
  banner "Act 3 · Broken release → automatic rollback"
  say "Building a release that passes its tests but crashes on startup (the DEMO 3 block, enabled in a temp copy)."
  mkdir -p "$WORK/app"
  # Copy the app without node_modules, then enable the DEMO 3 block in the copy only.
  tar -C app --exclude node_modules -cf - . | tar -C "$WORK/app" -xf -
  sed -e 's|^// if (process.env.NODE_ENV|if (process.env.NODE_ENV|' \
      -e 's|^//   console.error(JSON.stringify({ msg: "DATABASE_URL|  console.error(JSON.stringify({ msg: "DATABASE_URL|' \
      -e 's|^//   process.exit(1);|  process.exit(1);|' \
      -e 's|^// }$|}|' app/src/server.js > "$WORK/app/src/server.js"
  grep -q '^if (process.env.NODE_ENV' "$WORK/app/src/server.js" || { warn "could not enable the DEMO 3 block"; exit 1; }
  run docker build -q --target runtime --build-arg APP_VERSION=broken -t hello-app:broken "$WORK/app"
  run kind load docker-image hello-app:broken --name "$CLUSTER"
  pause "deploy the broken release (with traffic running)"

  local log="$WORK/rollback.log"
  start_traffic normal "$log"
  # From here on, this is the same logic as the Jenkinsfile's "Deploy to EKS" stage.
  run kubectl -n app set image deploy/hello-app hello-app=hello-app:broken
  kubectl -n app annotate deploy/hello-app kubernetes.io/change-cause="demo: broken release" --overwrite >/dev/null
  if ! run kubectl -n app rollout status deploy/hello-app --timeout="$ROLLOUT_TIMEOUT"; then
    echo
    run kubectl -n app get pods
    local bad_pod
    bad_pod="$(kubectl -n app get pods --no-headers | awk '/CrashLoopBackOff|Error/{print $1; exit}')"
    if [ -n "$bad_pod" ]; then
      say "Why is it crashing? (last log line of the crashed container)"
      printf '\033[1;33m$ kubectl -n app logs %s --previous --tail=1\033[0m\n' "$bad_pod"
      # The container may be mid-restart, when its logs are briefly unavailable (kubectl then prints
      # "unable to retrieve container logs" as if it were log output), so look for the real fatal line and retry.
      local line=""
      for _ in 1 2 3 4 5 6 7 8; do
        line="$( { kubectl -n app logs "$bad_pod" --tail=5 2>/dev/null; kubectl -n app logs "$bad_pod" --previous --tail=5 2>/dev/null; } \
                 | grep -m1 'DATABASE_URL' || true)"
        [ -n "$line" ] && break
        sleep 2
      done
      echo "${line:-(logs not available yet; try: kubectl -n app logs $bad_pod --previous)}"
    fi
    warn "Rollout failed → rolling back"
    run kubectl -n app rollout undo deploy/hello-app
    run kubectl -n app rollout status deploy/hello-app --timeout=120s
  fi
  stop_traffic

  local total bad
  total="$(count_total "$log")"; bad="$(count_bad "$log")"
  if [ "$bad" -eq 0 ]; then
    ok "rolled back, and $total/$total requests still returned HTTP 200: the old pods never stopped serving"
  else
    warn "$bad of $total requests failed"
  fi
  # Show that the Deployment is back on the healthy image with both pods Ready.
  run kubectl -n app get deploy hello-app \
    -o custom-columns='DEPLOYMENT:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
}

# ---------- Act 4: alerting ----------
alert_state() {
  curl -s localhost:9090/api/v1/alerts | python3 -c '
import json, sys
alerts = [a for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"] == "HelloAppHighErrorRate"]
print(alerts[0]["state"] if alerts else "inactive")' 2>/dev/null || echo "unknown"
}

act_alert() {
  banner "Act 4 · Alerting on user-facing errors"
  say "Rule: HelloAppHighErrorRate fires when more than 5% of requests fail for 1 minute."
  say "Sending traffic where ~30% of requests hit /error ..."
  local log="$WORK/alert.log"
  start_traffic errors "$log"
  local start state last=""
  start=$(date +%s)
  while :; do
    state="$(alert_state)"
    if [ "$state" != "$last" ]; then
      printf '\n  [%3ss] HelloAppHighErrorRate: \033[1m%s\033[0m' "$(( $(date +%s) - start ))" "$state"
      last="$state"
    else
      printf '.'
    fi
    [ "$state" = "firing" ] && break
    if [ $(( $(date +%s) - start )) -gt 360 ]; then warn "alert did not fire within 6 minutes"; break; fi
    sleep 5
  done
  echo
  stop_traffic
  if [ "$state" = "firing" ]; then
    ok "alert FIRING after $(( $(date +%s) - start ))s ($(count_bad "$log") of $(count_total "$log") requests failed); Alertmanager routes it to Slack"
  fi
  say "Show it on screen:"
  say "  Prometheus alerts:  http://localhost:9090/alerts"
  say "  Grafana dashboard:  http://localhost:3000  → Dashboards → hello-app: Golden Signals"
  say "  Grafana login:      admin  (password command: see docs/DEMO.md)"
}

# ---------- main ----------
case "$ACT" in
  all|app|rollout|rollback|alert) ;;
  *) echo "Usage: $0 [all|app|rollout|rollback|alert]" >&2; exit 1 ;;
esac

preflight
case "$ACT" in
  app)      act_app ;;
  rollout)  act_rollout ;;
  rollback) act_rollback ;;
  alert)    act_alert ;;
  all)
    act_app;      pause "Act 2: zero-downtime rolling update"
    act_rollout;  pause "Act 3: broken release and automatic rollback"
    act_rollback; pause "Act 4: alerting"
    act_alert
    pause "finish (stops the port-forwards)"
    ;;
esac
banner "Done"
