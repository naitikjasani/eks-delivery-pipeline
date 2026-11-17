// Jenkinsfile: the CI/CD pipeline for hello-app, written as code (declarative pipeline syntax).
//
// Stages: Preflight → Test → Build → Push to ECR → Deploy to EKS (with automatic rollback).
// Push and Deploy run only when the global env var DEPLOY_ENABLED is 'true', so you can practise
// Test + Build locally for free, without any AWS account.
//
// Configured by hand in the Jenkins UI (see docs/RUNBOOK.md), never stored in git:
//   Global env vars:   AWS_REGION, CLUSTER_NAME, ECR_REPO_URL, DEPLOY_ENABLED
//   Secret-text creds: aws-access-key-id, aws-secret-access-key   (the least-privilege jenkins-ci user)
//
// Shell steps use '''single-quoted''' Groovy strings, so Groovy does NOT substitute ${...} itself; the
// shell does. That way secrets never end up inside the Groovy-built command text (Jenkins warns about this).
// Each one starts with #!/bin/bash so `set -euo pipefail` works (/bin/sh on Debian is the more limited dash):
//   -e stop at the first error, -u error on unset variables, -o pipefail a failing command in a pipe fails the step.
pipeline {
  // Run on any available executor. Our local Jenkins has just the built-in one.
  agent any

  options {
    // Prefix every console line with the time, which helps when reading how long a rollout took.
    timestamps()
    // Kill a stuck build after 20 minutes instead of blocking the executor forever.
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds()                    // two deploys at once would fight each other
    // Keep only the last 20 builds, so the Jenkins volume doesn't fill up.
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { pollSCM('H/2 * * * *') }            // local Jenkins can't receive GitHub webhooks, so it polls every ~2 min

  environment {
    APP_DIR = 'app'
    NAMESPACE = 'app'
    DEPLOYMENT = 'hello-app'
    KUBECONFIG = "${WORKSPACE}/.kube/config"     // per-build kubeconfig, deleted in post
  }

  stages {
    stage('Preflight') {
      steps {
        script {
          // Fail fast with a clear message, instead of a confusing AWS error three stages later.
          if (env.DEPLOY_ENABLED == 'true') {
            def missing = ['AWS_REGION', 'CLUSTER_NAME', 'ECR_REPO_URL'].findAll { !env."${it}"?.trim() }
            if (missing) {
              error("DEPLOY_ENABLED=true but these global environment variables are not set: ${missing.join(', ')}. " +
                    "Set them in Manage Jenkins → System → Global properties.")
            }
            // The registry host is everything before the first '/', e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com
            env.ECR_REGISTRY = env.ECR_REPO_URL.split('/')[0]
          }
          // The image tag is the short (7-character) git commit SHA, so every image traces back to its exact commit.
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          echo "Image tag: ${env.IMAGE_TAG}   DEPLOY_ENABLED=${env.DEPLOY_ENABLED ?: 'false'}"
        }
      }
    }

    stage('Test') {
      steps {
        // Builds only the "test" stage of app/Dockerfile, which runs `npm test`. A failing test fails the build
        // here, and nothing later runs. Jenkins needs no Node.js installed; the tests run inside Docker.
        sh '''#!/bin/bash
          set -euo pipefail
          docker build --target test -t "hello-app:test-${IMAGE_TAG}" "${APP_DIR}"
        '''
      }
    }

    stage('Build') {
      steps {
        // Builds the small production image, with the git SHA baked in as APP_VERSION (GET / shows it).
        // Locally (DEPLOY_ENABLED != true) there is no ECR URL, so we use a plain local name instead.
        sh '''#!/bin/bash
          set -euo pipefail
          if [ "${DEPLOY_ENABLED:-false}" = "true" ]; then
            IMAGE="${ECR_REPO_URL}:${IMAGE_TAG}"
          else
            IMAGE="hello-app:${IMAGE_TAG}"
          fi
          docker build --target runtime --build-arg APP_VERSION="${IMAGE_TAG}" -t "${IMAGE}" "${APP_DIR}"
          echo "Built ${IMAGE}"
        '''
      }
    }

    stage('Push to ECR') {
      when { environment name: 'DEPLOY_ENABLED', value: 'true' }
      steps {
        // withCredentials exposes the two secret-text credentials as environment variables for this block only,
        // and masks them as **** if they ever appear in the log. The AWS CLI reads these variable names automatically.
        withCredentials([
          string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          sh '''#!/bin/bash
            set -euo pipefail
            # ECR tags are IMMUTABLE: pushing the same tag twice is an error. If this commit's image is already
            # in ECR (e.g. you re-ran the build), skip the push; the existing image is identical anyway.
            if aws ecr describe-images --region "${AWS_REGION}" --repository-name hello-app \
                 --image-ids imageTag="${IMAGE_TAG}" >/dev/null 2>&1; then
              echo "Image hello-app:${IMAGE_TAG} already exists in ECR, skipping push."
              exit 0
            fi
            # Get a temporary (12-hour) registry password and pipe it straight into docker login.
            # --password-stdin keeps it out of the process list and the build log.
            aws ecr get-login-password --region "${AWS_REGION}" \
              | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
            docker push "${ECR_REPO_URL}:${IMAGE_TAG}"
          '''
        }
      }
    }

    stage('Deploy to EKS') {
      when { environment name: 'DEPLOY_ENABLED', value: 'true' }
      steps {
        withCredentials([
          string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          sh '''#!/bin/bash
            set -euo pipefail
            # Write a kubeconfig for this build only (KUBECONFIG points into the workspace). It authenticates
            # as the jenkins-ci IAM user, which EKS maps to "edit" rights in namespace "app" only.
            aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"

            # Put the real image into the manifest and apply it. The first run creates the Deployment;
            # later runs change only the image, which starts a rolling update.
            sed "s|IMAGE_PLACEHOLDER|${ECR_REPO_URL}:${IMAGE_TAG}|" k8s/deployment.yaml | kubectl apply -f -
            kubectl apply -f k8s/service.yaml

            # Record WHY this revision exists; it shows up in `kubectl rollout history`.
            kubectl -n "${NAMESPACE}" annotate deploy/"${DEPLOYMENT}" \
              kubernetes.io/change-cause="jenkins #${BUILD_NUMBER} ${IMAGE_TAG}" --overwrite

            # Automatic rollback: wait up to 120 s for the new pods to become Ready. If they never do
            # (e.g. they crash on startup, like Demo 3), put the previous version back and fail the build.
            # Thanks to maxUnavailable: 0, the old pods kept serving traffic the whole time.
            if ! kubectl -n "${NAMESPACE}" rollout status deploy/"${DEPLOYMENT}" --timeout=120s; then
              echo "Rollout failed → rolling back"
              kubectl -n "${NAMESPACE}" rollout undo deploy/"${DEPLOYMENT}"
              kubectl -n "${NAMESPACE}" rollout status deploy/"${DEPLOYMENT}" --timeout=120s
              exit 1
            fi
          '''
        }
      }
    }
  }

  post {
    always {
      // Clean up even when the build failed, so no credentials, kubeconfigs or big test images pile up.
      // No `set -u` here: if Preflight failed, IMAGE_TAG or ECR_REGISTRY may not exist, and cleanup must still run.
      sh '''#!/bin/bash
        if [ -n "${ECR_REGISTRY:-}" ]; then docker logout "${ECR_REGISTRY}" || true; fi
        rm -rf .kube
        docker image rm "hello-app:test-${IMAGE_TAG:-none}" || true
      '''
      // Delete the workspace (ws-cleanup plugin), so every build starts from a clean checkout.
      cleanWs()
    }
    success { echo "Deployed ${env.IMAGE_TAG}" }
    failure { echo "Pipeline failed. If the deploy stage failed, the previous version was restored." }
  }
}
