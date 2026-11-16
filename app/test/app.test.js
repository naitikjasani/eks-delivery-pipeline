// app.test.js: automated tests, run by `npm test` (which runs `node --test`).
//
// node:test is Node's built-in test runner, so we need no extra framework (like Jest).
// supertest sends HTTP requests straight to the Express app in memory, without opening a real port.
// These tests also run inside Docker (`docker build --target test`), and if any fails, Jenkins stops the pipeline.
import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { createApp, markShuttingDown } from "../src/app.js";

test("GET / returns 200 with message, version and pod", async () => {
  const res = await request(createApp()).get("/");
  assert.equal(res.status, 200);
  assert.ok("message" in res.body, "body has message");
  assert.ok("version" in res.body, "body has version");
  assert.ok("pod" in res.body, "body has pod");
});

test("GET /health/live returns 200", async () => {
  const res = await request(createApp()).get("/health/live");
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { status: "ok" });
});

test("GET /health/ready returns 200, then 503 after markShuttingDown()", async () => {
  // A fresh app instance resets the readiness flag, so this test doesn't depend on test order.
  const app = createApp();

  const before = await request(app).get("/health/ready");
  assert.equal(before.status, 200);
  assert.deepEqual(before.body, { status: "ready" });

  // Simulate what server.js does when Kubernetes sends SIGTERM.
  markShuttingDown();

  const after = await request(app).get("/health/ready");
  assert.equal(after.status, 503);
  assert.deepEqual(after.body, { status: "shutting-down" });
});

test("GET /error returns 500", async () => {
  const res = await request(createApp()).get("/error");
  assert.equal(res.status, 500);
  assert.deepEqual(res.body, { error: "simulated failure" });
});

test("GET /metrics returns 200 and contains http_requests_total after a request to /", async () => {
  const app = createApp();
  // Make one real request first so the counter has at least one recorded value.
  await request(app).get("/");

  const res = await request(app).get("/metrics");
  assert.equal(res.status, 200);
  assert.match(res.text, /http_requests_total/);
});

test("GET /nope returns 404", async () => {
  const res = await request(createApp()).get("/nope");
  assert.equal(res.status, 404);
  assert.deepEqual(res.body, { error: "not found" });
});
