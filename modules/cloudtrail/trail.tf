# --- Organization trail (environments/management only) ------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  count = var.create_trail ? 1 : 0

  name              = "/patheya-express/${var.name_prefix}/cloudtrail"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "cloudtrail", Purpose = "organization-trail-cloudwatch-feed" })
}

data "aws_iam_policy_document" "trail_to_cloudwatch_assume" {
  count = var.create_trail ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trail_to_cloudwatch" {
  count = var.create_trail ? 1 : 0

  name               = "${var.name_prefix}-cloudtrail-to-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.trail_to_cloudwatch_assume[0].json

  tags = merge(var.tags, { Application = "cloudtrail", Purpose = "cloudtrail-to-cloudwatch-delivery-role" })
}

data "aws_iam_policy_document" "trail_to_cloudwatch_delivery" {
  count = var.create_trail ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.trail[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "trail_to_cloudwatch_delivery" {
  count = var.create_trail ? 1 : 0

  name   = "${var.name_prefix}-cloudtrail-to-cloudwatch-delivery"
  role   = aws_iam_role.trail_to_cloudwatch[0].id
  policy = data.aws_iam_policy_document.trail_to_cloudwatch_delivery[0].json
}

resource "aws_cloudtrail" "organization" {
  count = var.create_trail && var.existing_bucket_name != null ? 1 : 0

  name                       = "${var.name_prefix}-organization-trail"
  s3_bucket_name             = var.existing_bucket_name
  is_organization_trail      = true
  is_multi_region_trail      = true
  enable_log_file_validation = true
  # No explicit kms_key_id here, deliberately: this trail's destination bucket lives in a
  # different AWS account (environments/security), and specifying a Management-owned KMS key
  # here creates a cross-account KMS relationship that key's policy does not authorize
  # (confirmed root cause, Phase 2I: CreateTrail's InsufficientEncryptionPolicyException).
  # Omitting this lets CloudTrail rely on the destination bucket's own existing default SSE-KMS
  # encryption (Security's own, same-account key), which is already sufficient and requires no
  # cross-account grant. The CloudWatch Logs group below is a same-account (Management) resource
  # and correctly keeps its own kms_key_id, unaffected by this change.
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_cloudwatch[0].arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${data.aws_partition.current.partition}:s3:::"] # every bucket, every account in the org — data-plane S3 access is exactly the activity an org-wide trail exists to capture
    }
  }

  tags = merge(var.tags, { Application = "cloudtrail", Purpose = "organization-trail" })
}
