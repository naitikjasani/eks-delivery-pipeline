# Multi-stage Dockerfile for hello-app.
#
# One file, three stages:
#   deps    → installs every npm package (including dev ones such as supertest)
#   test    → runs the tests; Jenkins builds it with:  docker build --target test .
#   runtime → the small production image that is pushed to ECR and runs in Kubernetes
#
# BuildKit (Docker's default builder) only builds the stages the chosen --target needs.
# A plain `docker build .` builds the LAST stage (runtime), which doesn't depend on "test",
# so the tests are SKIPPED. That's why Jenkins runs `--target test` as its own separate step.

# ---------- Stage 1: install ALL deps (incl. dev) once, cached by package*.json ----------
# Alpine-based Node 24 image: small, and Docker picks the arm64 variant automatically on Apple Silicon / Graviton.
FROM node:24-alpine AS deps
WORKDIR /app
# Copy ONLY the package files first. Docker caches each step, so as long as package*.json doesn't change,
# the slow `npm ci` below is reused from cache even when the source code changes.
COPY package*.json ./
# npm ci installs exactly what package-lock.json says (reproducible), unlike `npm install`.
RUN npm ci

# ---------- Stage 2: run tests. Jenkins runs: docker build --target test . ----------
# If a test fails, `npm test` exits non-zero, the build fails, and nothing is pushed.
FROM deps AS test
# Bring in the source code and tests (.dockerignore keeps node_modules and .git out).
COPY . .
RUN npm test

# ---------- Stage 3: small production image (no dev deps, no tests) ----------
# Start again from a clean base, so nothing from the deps/test stages (like supertest) leaks in.
FROM node:24-alpine AS runtime
# Tells Express and npm we're in production (faster, less verbose). DEMO 3 also checks this value.
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
# Install only runtime dependencies, then delete npm's download cache to keep the image small.
RUN npm ci --omit=dev && npm cache clean --force
# Only the application code; tests aren't needed at runtime.
COPY src ./src
# Jenkins passes the git SHA: --build-arg APP_VERSION=a1b2c3d. ARG exists only at build time,
# so we copy it into ENV to make it visible to the running app (GET / shows it).
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
# Run as the non-root "node" user (uid 1000); the Deployment's securityContext requires it.
# (Dockerfile comments must be on their own line, not after an instruction.)
USER node
# Documentation only: tells readers (and tools) which port the app listens on.
EXPOSE 3000
# Exec form (a JSON array), so node is PID 1 and receives SIGTERM directly. With the shell form,
# /bin/sh would receive the signal instead and graceful shutdown would not happen.
CMD ["node", "src/server.js"]
