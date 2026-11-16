// server.js: starts the HTTP server and shuts it down gracefully.
//
// This is the container's entry point (CMD in the Dockerfile). Tests never import this file,
// so they don't open ports or install signal handlers.
import config from "./config.js";
import { createApp, markShuttingDown } from "./app.js";

// --- DEMO 3 (broken release) -------------------------------------------------
// To simulate a release that passes tests but crashes in production, uncomment:
// if (process.env.NODE_ENV === "production" && !process.env.DATABASE_URL) {
//   console.error(JSON.stringify({ msg: "DATABASE_URL is required", level: "fatal" }));
//   process.exit(1);
// }
// ------------------------------------------------------------------------------

// Logs are single-line JSON written to stdout. Kubernetes collects each container's stdout
// (kubectl logs), and JSON lines are easy to search and parse with log tools.
function log(fields) {
  console.log(JSON.stringify({ time: new Date().toISOString(), ...fields }));
}

const server = createApp().listen(config.port, () => {
  log({ msg: "listening", port: config.port, version: config.version });
});

// Graceful shutdown: this is what makes rolling updates zero-downtime.
// During a rollout Kubernetes sends SIGTERM to an old pod (after the preStop sleep). We then:
//   1. mark ourselves "not ready", so /health/ready returns 503 and no NEW traffic is routed to us;
//   2. server.close() stops accepting new connections but lets in-flight requests finish;
//   3. exit with code 0 once everything has finished.
// If something hangs (e.g. a stuck keep-alive connection), we force-exit after 10 s. That is well within
// terminationGracePeriodSeconds (30 s), after which Kubernetes would SIGKILL us anyway.
// SIGINT (Ctrl-C) gets the same treatment so local runs behave like Kubernetes.
let stopping = false;
function shutdown(signal) {
  if (stopping) return; // a second signal while already stopping changes nothing
  stopping = true;

  markShuttingDown();
  log({ msg: "shutting down", signal });

  server.close(() => {
    log({ msg: "server closed, exiting" });
    process.exit(0);
  });

  // Close idle keep-alive connections now, so server.close() doesn't wait for them to time out.
  // Connections that are busy with a request are left alone until that request finishes.
  server.closeIdleConnections();

  // Safety net. unref() means this timer alone won't keep the process alive if everything closed cleanly.
  setTimeout(() => {
    log({ msg: "forced exit after 10s", level: "error" });
    process.exit(1);
  }, 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
