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
  count = var.create_trail ? 1 : 0

  name                       = "${var.name_prefix}-organization-trail"
  s3_bucket_name             = var.existing_bucket_name
  is_organization_trail      = true
  is_multi_region_trail      = true
  enable_log_file_validation = true
  kms_key_id                 = var.kms_key_arn
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
