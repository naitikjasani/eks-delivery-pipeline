// config.js: the ONE place where the app reads its settings from environment variables.
//
// Why environment variables? The same Docker image must run on a laptop, in kind and on EKS.
// Only the settings change (Kubernetes injects them from deployment.yaml), never the code.
//
// Rule: this file must never throw or exit when a variable is missing, because the tests import it
// without setting anything. Every setting therefore has a safe default.
import os from "node:os";

const config = {
  // Port the HTTP server listens on. Number(undefined) is NaN, and NaN || 3000 gives 3000.
  port: Number(process.env.PORT) || 3000,

  // Text returned by GET /. Change this to see a new version roll out (RUNBOOK Demo 2).
  // "??" (not "||") so that an intentionally empty GREETING="" is respected.
  greeting: process.env.GREETING ?? "Hello from hello-app",

  // Which build is running. The Dockerfile sets it to the git SHA, so every response
  // tells you exactly which commit answered.
  version: process.env.APP_VERSION ?? "dev",

  // Which pod answered. Kubernetes injects POD_NAME (see k8s/deployment.yaml). Outside Kubernetes
  // we fall back to the machine's hostname (inside Docker that's the container ID).
  podName: process.env.POD_NAME ?? os.hostname(),
};

export default config;
