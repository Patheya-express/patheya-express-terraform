# --- S3 destination bucket (environments/security only) ----------------------------------------

resource "aws_s3_bucket" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = "${var.name_prefix}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  # Phase 0 remediation: Object Lock can only be enabled at bucket creation — see
  # enable_object_lock's description for why this is safe to turn on now and would not be safe to
  # retrofit onto a bucket that's already been applied for real.
  object_lock_enabled = var.enable_object_lock

  tags = merge(var.tags, {
    Application = "cloudtrail"
    Purpose     = "organization-trail-log-archive"
  })
}

resource "aws_s3_bucket_versioning" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Object Lock requires versioning enabled on the bucket (aws_s3_bucket_versioning above) before its
# lock configuration can be applied — the explicit dependency keeps that ordering correct even
# though object_lock_enabled on the bucket resource itself already implies versioning.
resource "aws_s3_bucket_object_lock_configuration" "trail" {
  count = var.create_destination_bucket && var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Indefinite retention in Standard for 1 year (fast retrieval for an active investigation), then
# Glacier for long-term compliance archive — CloudTrail logs are never deleted by an age-based
# rule; only versioning/lifecycle *transitions* storage class, matching platform-standards.md
# Section 11's "1 year cold" as a floor, not a ceiling, for this specific compliance-sensitive log type.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "archive-after-1-year"
    status = "Enabled"

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

data "aws_iam_policy_document" "trail_bucket_policy" {
  count = var.create_destination_bucket ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${var.management_account_id}:trail/${var.name_prefix}-organization-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${var.organization_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${var.management_account_id}:trail/${var.name_prefix}-organization-trail"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail[0].arn, "${aws_s3_bucket.trail[0].arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket_policy[0].json
}
