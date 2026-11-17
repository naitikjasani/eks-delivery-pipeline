# ADR 0005: S3 remote state with native lock files (no DynamoDB)

**Status:** Accepted

## Context
Terraform state records what exists and, here, also contains the Jenkins secret key. It must be durable,
encrypted, private, and protected against two concurrent `apply` runs. The traditional answer was an S3
bucket plus a DynamoDB table for locking.

## Decision
A small `infra/bootstrap` configuration (with **local** state, because a bucket can't store the state of its own
creation) creates an S3 bucket with versioning, SSE-S3 encryption and all four public-access blocks.
`infra/envs/dev` uses it with `use_lockfile = true`, Terraform ≥ 1.10's S3-native locking. No DynamoDB table.

## Consequences
- One less resource to create, pay for and forget to delete.
- Versioning lets a corrupted state write be rolled back.
- `force_destroy = true` on the bucket allows complete cleanup at the end of the project (a deliberate demo trade-off).
- Requires Terraform ≥ 1.10, which is enforced in every `versions.tf`.

## In production
The same S3-native locking, with a KMS key and a bucket policy restricting access to the CI role, `force_destroy`
off, and separate state per environment/account.

Implemented in [`infra/bootstrap/`](../../infra/bootstrap/) and [`infra/envs/dev/backend.hcl.example`](../../infra/envs/dev/backend.hcl.example).
