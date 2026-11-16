// metrics.js: Prometheus metrics for the app.
//
// Prometheus works on a "pull" model: every 15 s it visits GET /metrics and reads plain-text numbers.
// prom-client keeps those numbers in memory and formats them for us.
import client from "prom-client";

// A registry is the collection of all metrics that /metrics prints.
// We use the library's default (global) registry, so there's exactly one per process.
export const register = client.register;

// Built-in process metrics: CPU, memory, event-loop lag, garbage collection, and so on.
// These cover the "saturation" golden signal for free.
client.collectDefaultMetrics({ register });

// Counter = a number that only goes up. Prometheus computes the rate (requests per second) from it.
// Covers the "traffic" and "errors" golden signals (errors = status_code 5xx).
export const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests handled",
  labelNames: ["method", "route", "status_code"],
  registers: [register],
});

// Histogram = counts how many requests fell into each duration bucket (in seconds).
// Grafana turns the buckets into p50/p95/p99 latency, the "latency" golden signal.
// The buckets run from 10 ms to 5 s, which covers fast requests and the /slow endpoint (capped at 5 s).
export const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

// Paths we deliberately do NOT measure. Prometheus scrapes /metrics every 15 s and the kubelet
// calls the health probes every 5 to 10 s. Counting them would drown out real user traffic and
// make the request-rate and latency graphs misleading.
function isIgnored(path) {
  return path === "/metrics" || path.startsWith("/health/");
}

// Express middleware: start a timer when a request arrives, record the metrics when the response is sent.
export function metricsMiddleware(req, res, next) {
  if (isIgnored(req.path)) return next();

  // startTimer() returns a function. Calling it records the elapsed seconds into the histogram.
  const endTimer = httpRequestDuration.startTimer();

  // "finish" fires once the response has been fully handed to the operating system. Only then do we
  // know the final status code and the route Express matched.
  res.on("finish", () => {
    // IMPORTANT: the "route" label must be the route PATTERN (e.g. "/slow"), never the raw URL
    // (e.g. "/slow?ms=812" or "/nope/123"). Every distinct label value creates a new time series in
    // Prometheus. Raw URLs are unbounded (anyone can request any path), so they would create unlimited
    // series and eventually exhaust Prometheus' memory. This problem is called "high cardinality".
    // Requests that matched no route (404s) all share the single value "unmatched".
    const labels = {
      method: req.method,
      route: req.route?.path ?? "unmatched",
      status_code: String(res.statusCode),
    };
    httpRequestsTotal.inc(labels);
    endTimer(labels);
  });

  next();
}
