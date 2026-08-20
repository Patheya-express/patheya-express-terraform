resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "patheya-express/${each.value}"
  image_tag_mutability = "IMMUTABLE" # platform-standards.md Section 4: image tags are never reused — enforced here, not just by convention

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Application = each.value
    Purpose     = "container-image-registry-${each.value}"
  })
}

# Continuous rescanning (not just at push time) — a CVE disclosed after an image was pushed and
# already scanned clean still gets caught (cloud-architecture-blueprint.md Section 11's Trivy
# Operator does the in-cluster equivalent for running images; this is ECR's own native version for
# images sitting in the registry, pushed or not yet deployed).
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "patheya-express/*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.keep_last_n_tagged_images} most recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_last_n_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Cross-account pull — every account in the organization (development/staging/production EKS
# nodes) can pull images from this account's registry; no push permission is granted here (that's
# the Terraform CI role's own, narrower policy in the calling environment, not a blanket
# repository-policy grant).
data "aws_iam_policy_document" "cross_account_pull" {
  statement {
    sid    = "AllowOrgMemberPull"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

resource "aws_ecr_repository_policy" "cross_account_pull" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy     = data.aws_iam_policy_document.cross_account_pull.json
}
