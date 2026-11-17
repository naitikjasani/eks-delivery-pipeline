# jenkins/Dockerfile: a local Jenkins server with the tools our pipeline needs.
#
# The official Jenkins image doesn't include docker, aws or kubectl, so we add them here.
# Build and start it with:  cd jenkins && docker compose up -d --build

# Long-term-support Jenkins on Java 21 (Debian-based). The "lts" line gets only stable, well-tested releases.
FROM jenkins/jenkins:lts-jdk21

# Installing system packages needs root.
USER root

# Basic tools: curl downloads the other tools, unzip unpacks the AWS CLI, git checks out our repo,
# ca-certificates/gnupg verify that downloads really come from Docker. Deleting the apt lists afterwards keeps the image smaller.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip git \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI + buildx plugin from Docker's official apt repo. We install ONLY the client, NOT the daemon:
# the client talks to the Mac's Docker through the mounted /var/run/docker.sock (see docker-compose.yml),
# so images built here appear in your normal Docker Desktop.
# `dpkg --print-architecture` prints arm64 on Apple Silicon and amd64 on Intel, so the right packages are chosen.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# AWS CLI v2, used to log in to ECR and to write the kubeconfig for EKS.
# `uname -m` prints aarch64 (Apple Silicon) or x86_64 (Intel), which matches AWS's download file names.
RUN ARCH="$(uname -m)" \
 && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
 && unzip -q /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install \
 && rm -rf /tmp/aws /tmp/awscliv2.zip

# kubectl (latest stable release), used to deploy to EKS and roll back.
# stable.txt contains the newest version number, e.g. v1.37.0. The binary's path uses arm64/amd64, like dpkg.
RUN KARCH="$(dpkg --print-architecture)" \
 && KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" \
 && curl -fsSL "https://dl.k8s.io/release/${KVER}/bin/linux/${KARCH}/kubectl" -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl

# Pre-install our plugins at build time, so you can choose "install no plugins" in the setup wizard
# and get exactly the same, known set every time.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# We deliberately stay root, so the container can use the host's Docker socket without matching group IDs
# between the Mac and the container. This is acceptable ONLY because this Jenkins runs locally on a laptop
# and is never exposed to the internet. Never run a shared or public Jenkins as root.
USER root
