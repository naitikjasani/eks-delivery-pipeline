# main.tf: the private Docker image registry (ECR) that Jenkins pushes to and EKS pulls from.

resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # IMMUTABLE: once "hello-app:a1b2c3d" is pushed, that tag can never point to a different image.
  # A tag therefore always means the same image, which is what makes rollbacks trustworthy:
  # rolling back to a3f9e1c really runs the code from commit a3f9e1c.
  image_tag_mutability = "IMMUTABLE"

  # Scan each image for known vulnerabilities (CVEs) when it's pushed. Basic scanning is free.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Lets `terraform destroy` delete the repository even if it still contains images.
  # Without this, destroy would fail and the repo (and its storage cost) would linger.
  force_delete = true
}

# Housekeeping: automatically expire everything beyond the newest N images, so storage never grows.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest ${var.keep_images} images"
      selection = {
        tagStatus   = "any" # applies to tagged and untagged images alike
        countType   = "imageCountMoreThan"
        countNumber = var.keep_images
      }
      action = {
        type = "expire"
      }
    }]
  })
}
