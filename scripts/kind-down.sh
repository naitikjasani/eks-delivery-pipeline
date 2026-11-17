#!/usr/bin/env bash
# kind-down.sh: delete the local kind cluster "devops-lab" and everything in it.
# It's free to run, and frees up the memory Docker Desktop was using. Recreate it with ./scripts/kind-up.sh.
#
# Usage: ./scripts/kind-down.sh

set -euo pipefail

kind delete cluster --name devops-lab
