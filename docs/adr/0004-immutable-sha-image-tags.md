# ADR 0004: Image tag = git SHA, immutable ECR tags

**Status:** Accepted

## Context
Deployments and rollbacks are only trustworthy if a tag always refers to the same image. Tags like `latest` can
be overwritten, which makes it impossible to know what's actually running, and makes `IfNotPresent` pulls stale.

## Decision
Jenkins tags every image with the 7-character commit SHA (`hello-app:a1b2c3d`) and bakes it into the app as
`APP_VERSION`. The ECR repository uses `image_tag_mutability = "IMMUTABLE"`. The pipeline checks
`ecr describe-images` first and skips the push if the tag already exists (re-running a build of the same commit).

## Consequences
- Every pod maps to an exact commit; `GET /` and `kubectl rollout history` show which one.
- `kubectl rollout undo` restores exactly the same bytes that ran before.
- A lifecycle policy keeps only the newest 5 images, so storage stays tiny. Rolling back further than 5 versions
  means rebuilding that commit.

## In production
The same pattern, plus image signing (cosign), a vulnerability-scan gate in the pipeline (e.g. Trivy), and
promotion of the *same* digest across environments instead of rebuilding.

Implemented in [`infra/modules/ecr/main.tf`](../../infra/modules/ecr/main.tf) and [`Jenkinsfile`](../../Jenkinsfile).
