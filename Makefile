# Makefile: short, memorable commands for the everyday tasks.
# Every target just calls the existing scripts or commands; open the target to see exactly what runs.
# Run `make` (or `make help`) to list them. Everything here is local and free; nothing touches AWS.

# Pinned kube-prometheus-stack version (keep in sync with monitoring/README.md).
CHART_VERSION := 93.3.0
# Always target the local kind cluster, so a stray `make` can never change the EKS cluster.
KIND_CONTEXT  := kind-devops-lab
# Traffic mode for `make traffic`: normal | errors | slow   (e.g. make traffic MODE=errors)
MODE          ?= normal

# These targets are commands, not files. .PHONY stops make from skipping them if a file with the same name exists.
.PHONY: help test lint tf-validate kind-up deploy monitoring traffic down

help: ## List the available commands
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

test: ## Run the app's tests locally and inside Docker (the same as Jenkins' Test stage)
	cd app && npm ci && npm test
	docker build --target test -t hello-app:test app

lint: ## Lint shell scripts, Dockerfiles and Kubernetes manifests (needs shellcheck, hadolint, kubeconform)
	shellcheck scripts/*.sh
	hadolint app/Dockerfile jenkins/Dockerfile
	kubeconform -strict -summary k8s/

tf-validate: ## Check Terraform formatting and validity (creates nothing in AWS)
	terraform fmt -check -recursive infra
	terraform -chdir=infra/bootstrap init -backend=false -input=false >/dev/null && terraform -chdir=infra/bootstrap validate
	terraform -chdir=infra/envs/dev init -backend=false -input=false >/dev/null && terraform -chdir=infra/envs/dev validate

kind-up: ## Create the local kind cluster "devops-lab" and the app namespace
	./scripts/kind-up.sh

deploy: ## Build the image, load it into kind and roll it out
	./scripts/kind-deploy.sh

# Same install command as monitoring/README.md (kind version). The Slack values file is added only if you created it.
monitoring: ## Install Prometheus, Grafana and Alertmanager on kind, plus our alerts and dashboard
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo update prometheus-community >/dev/null
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  --kube-context $(KIND_CONTEXT) --namespace monitoring --create-namespace --version $(CHART_VERSION) \
	  -f monitoring/values.yaml -f monitoring/values-kind.yaml \
	  $(if $(wildcard monitoring/alertmanager-slack.values.yaml),-f monitoring/alertmanager-slack.values.yaml) \
	  --wait --timeout 10m
	kubectl --context $(KIND_CONTEXT) apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard.yaml

traffic: ## Send traffic from inside the cluster until Ctrl-C (MODE=normal|errors|slow)
	./scripts/traffic.sh $(MODE)

down: ## Delete the local kind cluster
	./scripts/kind-down.sh
