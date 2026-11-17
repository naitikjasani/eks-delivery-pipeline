# RUNBOOK: doing this project step by step

This is **your** guide (the human). A coding agent builds the code from `PROJECT.md`; you set up accounts,
run the paid AWS session, record the demo and tear everything down.

| Part | What | Cost | Time |
|---|---|---|---|
| A | Install tools, create accounts, set up safety alarms | ₹0 | 1 hour |
| B | Practice everything on your Mac (local Kubernetes, local Jenkins) | ₹0 | 3–5 hours |
| C | The paid AWS session: build on EKS, demo, record, screenshot | ≈ ₹12/hour, ~3 hours | 3 hours |
| D | Tear down (after every paid session) | ₹0 | 15 min |
| E | Final cleanup (when you're done with the project) | ₹0 | 10 min |
| F | Troubleshooting | | |

> **Golden rule:** the AWS bill only runs while the EKS cluster exists. Do everything you can in Part B first.
> Start Part C only when Part B works end to end.

---

## Part A: One-time setup (free)

### A1. Install the missing tools
You already have Docker, AWS CLI, kubectl, git and Node. Install the rest:
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform     # NOT plain "brew install terraform": that one is stuck on an old version
brew install helm kind
terraform version    # must be 1.10 or newer
helm version && kind version
```

### A2. Give Docker Desktop enough memory
Docker Desktop → Settings → Resources → Memory **at least 6 GB**, CPUs 4 → Apply & restart.
(Local Kubernetes + Prometheus + Grafana + Jenkins together need it.)

### A3. Create the GitHub repo
1. github.com → New repository → name `eks-delivery-pipeline` → **Public** → no README (we have one).
2. In the project folder:
   ```bash
   cd ~/Projects/eks-delivery-pipeline
   git init -b main
   git add . && git commit -m "Project spec and docs"
   git remote add origin https://github.com/naitikjasani/eks-delivery-pipeline.git
   git push -u origin main
   ```

### A4. AWS account + safety alarms (do this BEFORE anything else on AWS)
1. Create an AWS account (needs a debit/credit card; AWS makes a small refundable verification charge).
2. **Secure the root user:** Account menu → Security credentials → assign MFA (Google Authenticator / Authy).
   Never create access keys for the root user.
3. **Budgets** (Billing and Cost Management → Budgets → Create budget). The first two budgets are free:
   - Template **"Zero spend budget"** → your email. (Emails you when spending goes above $0.01, so you know the meter is running.)
   - Template **"Monthly cost budget"** → amount **$5** → your email. Alerts at 85% and 100%.
4. **Check for credits:** Billing → Credits. New accounts often get free credits. If you have some, they may cover
   this whole project. (Don't assume it; check what your account shows.)
5. **Create an admin user for the CLI** (so you never use root):
   IAM → Users → Create user `naitik-admin` → "Attach policies directly" → `AdministratorAccess` → Create.
   Open the user → Security credentials → **Enable MFA** → Create access key → "Command Line Interface" → copy both values.
6. Configure the CLI with a named profile:
   ```bash
   aws configure --profile devops-lab
   #   Access key ID:     <paste>
   #   Secret access key: <paste>
   #   Region:            ap-south-1
   #   Output format:     json
   echo 'export AWS_PROFILE=devops-lab' >> ~/.zshrc && source ~/.zshrc
   aws sts get-caller-identity      # shows your account ID and naitik-admin → working
   ```

### A5. Slack webhook (for alerts)
1. Create a free Slack workspace (or use one you own) → create channel `#alerts`.
2. api.slack.com/apps → Create New App → From scratch → name `Alertmanager` → pick the workspace.
3. **Incoming Webhooks** → turn ON → "Add New Webhook to Workspace" → choose `#alerts` → copy the URL.
4. Later: `cp monitoring/alertmanager-slack.values.example.yaml monitoring/alertmanager-slack.values.yaml`
   and paste the URL in. That file is gitignored, so it will never be pushed. **Never paste the URL anywhere public.**

### A6. Have the code built
Give a coding agent this message:
> Read AGENTS.md and PROJECT.md. Build phases 1 to 7 in order. After each phase, run its Verify step and tell me the results. Do not run anything that creates AWS resources.

Read each file it creates. If a line makes no sense to you, ask the agent "why is this line here?". That's your interview prep.

---

## Part B: Free practice on your Mac

### B1. App + Docker
```bash
cd ~/Projects/eks-delivery-pipeline/app
npm ci && npm test
docker build --target test -t hello-app:test .
docker build --target runtime -t hello-app:local .
docker run --rm -p 3000:3000 hello-app:local      # open http://localhost:3000 → JSON. Ctrl-C to stop.
```
**Understand:** why three stages in the Dockerfile? Why `USER node`? (See BEGINNER_GUIDE.)

### B2. Local Kubernetes (kind)
```bash
cd ~/Projects/eks-delivery-pipeline
./scripts/kind-up.sh
./scripts/kind-deploy.sh
kubectl -n app get pods            # 2 pods, READY 1/1, STATUS Running
kubectl -n app describe pod <name> # read the Events at the bottom
kubectl -n app logs deploy/hello-app
```
Practice the zero-downtime check:
```bash
./scripts/traffic.sh normal                      # terminal 1: one line per request
kubectl -n app rollout restart deploy/hello-app  # terminal 2
kubectl -n app get pods -w                       # terminal 2: watch old pods leave, new ones arrive
```
Every line in terminal 1 should stay `200`.

### B3. Monitoring on kind
Follow `monitoring/README.md` (kind version of the install command). Then:
```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```
Open http://localhost:3000 (user `admin`) → Dashboards → **hello-app: Golden Signals**.
Run `./scripts/traffic.sh errors` → after ~2–3 minutes a Slack message appears in `#alerts`.

### B4. Practice the broken release (Demo 3) on kind
1. In `app/src/server.js`, uncomment the `DEMO 3` block.
2. `./scripts/kind-deploy.sh` → `kubectl -n app get pods -w` → new pods go `CrashLoopBackOff`,
   **old pods keep running** (that's `maxUnavailable: 0` protecting you).
   The script waits 120 s for the rollout and then exits with an error. That's expected here.
3. `kubectl -n app logs <crashing-pod>` → you see `DATABASE_URL is required`.
4. `kubectl -n app rollout undo deploy/hello-app` → back to healthy.
5. Re-comment the block and run `./scripts/kind-deploy.sh` again. On kind every build is tagged `hello-app:local`,
   so until you rebuild, the node's copy of that tag is still the broken image.

### B5. Local Jenkins (no AWS yet)
```bash
cd ~/Projects/eks-delivery-pipeline/jenkins
docker compose up -d --build
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```
1. Open http://localhost:8080 → paste the password → **"Select plugins to install" → None** (ours are pre-installed) → create your admin user.
2. Manage Jenkins → System → **Global properties → Environment variables** → add `DEPLOY_ENABLED` = `false`.
3. New Item → `hello-app` → **Pipeline** → Pipeline section: *Pipeline script from SCM* → Git →
   `https://github.com/naitikjasani/eks-delivery-pipeline.git` → Branch `*/main` → Script Path `Jenkinsfile` → Save.
4. **Build Now** → open the build → Stage View: Preflight ✔ Test ✔ Build ✔ (Push/Deploy skipped).
5. Break a test on purpose, commit, push → wait ~2 min (polling) → build turns red at **Test**. Revert it.

### B6. Terraform without spending
```bash
cd ~/Projects/eks-delivery-pipeline
aws eks describe-cluster-versions --region ap-south-1 --output table
#   → pick the NEWEST version whose status says STANDARD_SUPPORT (never EXTENDED_SUPPORT: that costs 6× more)
curl -s https://checkip.amazonaws.com          # your public IP

# 1) State bucket (costs ~₹0: a few KB in S3)
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply         # type "yes"; note the bucket name it prints

# 2) Prepare dev config
cp infra/envs/dev/backend.hcl.example     infra/envs/dev/backend.hcl         # put the bucket name in
cp infra/envs/dev/terraform.tfvars.example infra/envs/dev/terraform.tfvars   # set owner, version, your IP/32
terraform -chdir=infra/envs/dev init -backend-config=backend.hcl

# 3) Dry run: shows what WOULD be created. Creates nothing. Free.
terraform -chdir=infra/envs/dev plan
```
Read the plan. You should see roughly: 1 VPC, 2 subnets, 1 internet gateway, route table, IAM roles and policies,
1 EKS cluster, 1 node group, 1 ECR repo + lifecycle policy, 1 IAM user + key, access entry + policy association.
**There must be no NAT gateway, load balancer or EC2 instance.** If you see one, stop and ask.

✅ **Part B is done when** B1–B6 all work. Only then go to Part C.

---

## Part C: The paid AWS session (~3 hours, ≈ ₹40)

### C0. Before you start
- [ ] Part B fully works.
- [ ] Your IP hasn't changed since you wrote `terraform.tfvars` (`curl -s https://checkip.amazonaws.com`). If it has, update the tfvars file.
- [ ] Screen recorder ready (macOS: Cmd+Shift+5 → Record Entire Screen).
- [ ] You have a 3-hour block. **Write down the start time.**

### C1. Create the infrastructure (~15–20 min, the meter starts now)
```bash
cd ~/Projects/eks-delivery-pipeline
terraform -chdir=infra/envs/dev apply          # review, type "yes"
```
If the node group fails with a Spot capacity error: add `capacity_type = "ON_DEMAND"` to `terraform.tfvars`
and `apply` again (it costs ~₹2/hour more).

### C2. Connect kubectl to EKS
```bash
aws eks update-kubeconfig --region ap-south-1 --name eks-pipeline-dev
kubectl config current-context        # must mention eks-pipeline-dev (NOT kind-devops-lab)
kubectl get nodes -o wide             # 2 nodes Ready, arm64
kubectl create namespace app
```

### C3. Install monitoring on EKS (~5 min)
Same as `monitoring/README.md`, **EKS version** (no `values-kind.yaml`). Wait for `kubectl -n monitoring get pods` to show all Running.

### C4. Point Jenkins at AWS
```bash
terraform -chdir=infra/envs/dev output ecr_repository_url
terraform -chdir=infra/envs/dev output jenkins_access_key_id
terraform -chdir=infra/envs/dev output -raw jenkins_secret_access_key; echo
```
In Jenkins:
1. Manage Jenkins → Credentials → System → Global → Add Credentials → Kind **Secret text**:
   - ID `aws-access-key-id` → secret = the access key ID
   - ID `aws-secret-access-key` → secret = the secret key
2. Manage Jenkins → System → Global properties → Environment variables:
   `DEPLOY_ENABLED=true`, `AWS_REGION=ap-south-1`, `CLUSTER_NAME=eks-pipeline-dev`, `ECR_REPO_URL=<the url>`.

### C5. Demos (record each one)

**Demo 1: first deploy**
- Jenkins → `hello-app` → Build Now → all 5 stages green.
- `kubectl -n app get pods` → 2 Running. `kubectl -n app port-forward svc/hello-app 8081:80` → open http://localhost:8081.
- 📸 Jenkins stage view · `kubectl get nodes,pods -A` · ECR repo page in the AWS console showing the SHA-tagged image.

**Demo 2: zero-downtime update**
- Terminal 1: `./scripts/traffic.sh normal`.
- Change the greeting text in `app/src/config.js` → commit → push.
- Within ~2 min Jenkins starts on its own. Terminal 1 switches from the old version to the new one, **with no non-200 lines**.
- 📸 / 🎥 terminal 1 during the switch · `kubectl -n app rollout history deploy/hello-app`.

**Demo 3: automatic rollback**
- Uncomment the `DEMO 3` block in `app/src/server.js` → commit → push.
- Jenkins: Test ✔ (tests don't start the server) → Push ✔ → Deploy: new pods crash → after 120 s
  "Rollout failed → rolling back" → pipeline **red**.
- Terminal 1 (`traffic.sh normal`) kept answering `200` the whole time.
- 📸 Jenkins console log showing the rollback · `kubectl -n app rollout history`.
- **Re-comment the block → commit → push** (pipeline green again).

**Demo 4: monitoring + alert**
- `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80` → the dashboard.
- `./scripts/traffic.sh errors` for ~3 minutes → Slack `#alerts` gets **[FIRING] HelloAppHighErrorRate**.
  Stop the script → a few minutes later **[RESOLVED]**.
- 📸 Grafana dashboard with the error spike · the Slack message · Prometheus Alerts page (`port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090`).

**Demo 5: least privilege (quick, impressive in interviews)**
```bash
# Act as Jenkins for a minute. The ( ... ) subshell means these settings vanish afterwards.
(
  # Read the Jenkins keys first, while your admin profile is still active (terraform needs it to read state)
  export AWS_ACCESS_KEY_ID="$(terraform -chdir=infra/envs/dev output -raw jenkins_access_key_id)"
  export AWS_SECRET_ACCESS_KEY="$(terraform -chdir=infra/envs/dev output -raw jenkins_secret_access_key)"
  unset AWS_PROFILE                                            # now become Jenkins
  aws sts get-caller-identity                                  # → .../jenkins-ci
  aws s3 ls                                                    # → AccessDenied: Jenkins can't touch S3
  aws eks update-kubeconfig --region ap-south-1 --name eks-pipeline-dev --kubeconfig /tmp/jk
  kubectl --kubeconfig /tmp/jk -n app get pods                 # → works: Jenkins may manage "app"
  kubectl --kubeconfig /tmp/jk -n monitoring get pods          # → Forbidden: nothing else
  rm -f /tmp/jk
)
```
(Run it from the project folder.)
- 📸 both "denied" messages.

### C6. Save proof, then tear down immediately
Put screenshots in `docs/screenshots/`, reference them in `README.md`, commit, push. Then go to **Part D now**.

---

## Part D: Teardown (after EVERY paid session)

Do these **in order**:
```bash
cd ~/Projects/eks-delivery-pipeline
helm -n monitoring uninstall monitoring
kubectl delete namespace monitoring app
terraform -chdir=infra/envs/dev destroy        # type "yes", ~10–15 min
./scripts/teardown-check.sh                     # must end with ALL CLEAR
```
Then in Jenkins: set `DEPLOY_ENABLED=false` and delete the two AWS credentials (that key no longer exists anyway).

Next day: Billing → Bills → check the charges stopped. Expect a total of **₹30–100** for the whole project.

> The S3 state bucket from `infra/bootstrap` can stay between sessions (it costs ~₹0). Remove it in Part E.

## Part E: Final cleanup (when you're done with the project)
```bash
terraform -chdir=infra/bootstrap destroy        # deletes the state bucket
./scripts/teardown-check.sh                     # ALL CLEAR
kind delete cluster --name devops-lab
cd jenkins && docker compose down -v            # -v also deletes Jenkins data
```
Optional: IAM → delete `naitik-admin`'s access key. Keep the GitHub repo public; it's your proof.

---

## Part F: Troubleshooting

| Symptom | Likely cause → fix |
|---|---|
| `terraform init` says the backend bucket doesn't exist | `backend.hcl` bucket name is wrong → copy it from `terraform -chdir=infra/bootstrap output` |
| `apply` error mentions Spot / `UnfulfillableCapacity` | No Spot capacity right now → `capacity_type = "ON_DEMAND"` in tfvars |
| `kubectl` → `Unable to connect` / timeout | Your IP changed → update `public_access_cidrs` in tfvars → `apply` |
| `kubectl` → `You must be logged in` | Wrong AWS profile → `echo $AWS_PROFILE` should say `devops-lab` |
| Pods `ImagePullBackOff` on EKS | Image tag not in ECR, or wrong `ECR_REPO_URL` in Jenkins → check the ECR console |
| Pods `CrashLoopBackOff` | `kubectl -n app logs <pod> --previous` shows why (in Demo 3 that's expected) |
| Pods `Pending` | Not enough room on the nodes → `kubectl describe pod` → Events. Try `node_instance_types = ["t4g.large"]` |
| `exec format error` | Image built for the wrong CPU. Nodes are ARM (t4g) and your Mac is ARM, so this only happens if built elsewhere |
| Jenkins: `permission denied ... docker.sock` | Container isn't running as root → check `user: root` in `docker-compose.yml` |
| Jenkins: Push fails `tag already exists` | Same commit built twice; the pipeline should skip existing tags. Push a new commit |
| Jenkins never starts a build after a push | Polling runs every ~2 min, and only after the job has run once manually |
| No Slack message | Wrong webhook URL, or you installed monitoring without `-f monitoring/alertmanager-slack.values.yaml` → `helm upgrade` with it |
| Grafana shows "No data" | Is traffic running? Check Prometheus → Status → Targets: `hello-app` must be UP |
| `terraform destroy` hangs on VPC/subnets | Something outside Terraform (like a load balancer) is still attached → run `teardown-check.sh`, delete it in the console, re-run destroy |
| Forgot to destroy | Do Part D now. Every hour is ≈ ₹12 |
