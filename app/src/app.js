// app.js: builds the Express application but does NOT start listening.
//
// Why split app.js from server.js? Tests can import createApp() and send fake requests with supertest
// without opening a real network port or installing signal handlers.
import express from "express";
import config from "./config.js";
import { register, metricsMiddleware } from "./metrics.js";

// Readiness flag. It flips to true when Kubernetes asks the pod to stop (SIGTERM), so /health/ready
// starts answering 503 and Kubernetes stops sending new traffic to this pod.
// It lives at module level because server.js (the signal handler) and the routes must share it.
let shuttingDown = false;

// Called by server.js on SIGTERM/SIGINT.
export function markShuttingDown() {
  shuttingDown = true;
}

export function createApp() {
  // Each new app starts "ready". Tests rely on this to get a fresh state per test.
  shuttingDown = false;

  const app = express();

  // Don't advertise "X-Powered-By: Express". It tells attackers which framework to target.
  app.disable("x-powered-by");

  // Record request count and duration for every request (except /metrics and /health/*).
  app.use(metricsMiddleware);

  // Main endpoint. Returns WHICH version and WHICH pod answered, so during a rolling update you can
  // watch the responses switch from the old version to the new one.
  app.get("/", (req, res) => {
    res.json({ message: config.greeting, version: config.version, pod: config.podName });
  });

  // Liveness probe: "is the process alive and able to answer at all?"
  // If this fails 3 times in a row, Kubernetes RESTARTS the container. It stays 200 even while
  // shutting down, because a pod that is draining is still alive and must not be restarted.
  app.get("/health/live", (req, res) => {
    res.json({ status: "ok" });
  });

  // Readiness probe: "should this pod receive traffic right now?"
  // A failure only removes the pod from the Service's endpoints and never restarts it. We report
  // 503 once shutdown has begun, so no new requests arrive while in-flight ones finish.
  app.get("/health/ready", (req, res) => {
    if (shuttingDown) {
      return res.status(503).json({ status: "shutting-down" });
    }
    res.json({ status: "ready" });
  });

  // Deliberate failure, used to trigger the HelloAppHighErrorRate alert (scripts/traffic.sh errors).
  app.get("/error", (req, res) => {
    res.status(500).json({ error: "simulated failure" });
  });

  // Deliberately slow response, used to move the p95 latency graph (scripts/traffic.sh slow).
  // The wait is capped at 5000 ms so nobody can tie up the server with ?ms=999999999.
  app.get("/slow", async (req, res) => {
    const requested = Number(req.query.ms);
    const ms = Number.isFinite(requested) ? Math.min(Math.max(requested, 0), 5000) : 800;
    await new Promise((resolve) => setTimeout(resolve, ms));
    res.json({ waitedMs: ms });
  });

  // Prometheus scrape endpoint. The content type tells Prometheus which text format this is.
  app.get("/metrics", async (req, res) => {
    res.set("Content-Type", register.contentType);
    res.send(await register.metrics());
  });

  // Catch-all for unknown paths. It's registered last, so it only runs when no route above matched.
  // A JSON 404 is consistent with the other responses.
  app.use((req, res) => {
    res.status(404).json({ error: "not found" });
  });

  return app;
}
