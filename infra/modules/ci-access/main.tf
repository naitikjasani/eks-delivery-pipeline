# main.tf: a least-privilege identity for Jenkins.
#
# Jenkins can: push images to ONE ECR repository, look up ONE EKS cluster, and edit objects in ONE
# Kubernetes namespace. Nothing else, not even listing S3 buckets. If its key ever leaked, the damage
# ("blast radius") would be limited to redeploying hello-app.

resource "aws_iam_user" "jenkins" {
  name = var.user_name
}

# Inline policy = attached directly to this one user, and deleted together with it.
resource "aws_iam_user_policy" "jenkins" {
  name = "${var.user_name}-least-privilege"
  user = aws_iam_user.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Get a temporary password for `docker login`. AWS requires Resource "*" for this one action,
        # because the token is for the whole registry, not one repository. It grants no access by itself.
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # Everything `docker push` needs (check/upload layers, write the manifest), plus reading images
        # (BatchGetImage, GetDownloadUrlForLayer) and DescribeImages (the Jenkinsfile's "tag already exists?" check).
        # Scoped to our ONE repository ARN.
        Sid    = "EcrPushToOneRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
        ]
        Resource = var.ecr_repository_arn
      },
      {
        # `aws eks update-kubeconfig` needs this to learn the cluster's endpoint and certificate.
        # It does NOT grant any rights inside Kubernetes; those come from the access entry below.
        Sid      = "DescribeOneCluster"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = var.cluster_arn
      },
    ]
  })
}

# A long-lived access key for the user, pasted into Jenkins as two secret-text credentials.
# Honest trade-off: the secret ends up in Terraform state (encrypted in the S3 state bucket). That's acceptable
# for a short-lived demo, because `terraform destroy` deletes the key. In production, Jenkins would run on AWS
# and use an IAM role (instance profile / IRSA / OIDC), with no long-lived keys to leak at all.
resource "aws_iam_access_key" "jenkins" {
  user = aws_iam_user.jenkins.name
}

# EKS access entry: lets this IAM user authenticate to the Kubernetes API at all.
# (Modern replacement for editing the aws-auth ConfigMap, which was easy to break.)
resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_user.jenkins.arn
  type          = "STANDARD"
}

# What the user may do inside Kubernetes: AWS's "Edit" policy (create/update Deployments, Services, etc.),
# but ONLY in the app namespace. So Jenkins can change Deployments in "app" and nothing else.
# It can't read Secrets in other namespaces, touch monitoring, or create namespaces or other cluster-wide objects.
resource "aws_eks_access_policy_association" "jenkins" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_user.jenkins.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }

  # The access entry must exist before a policy can be associated with it.
  depends_on = [aws_eks_access_entry.jenkins]
}
