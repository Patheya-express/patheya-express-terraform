# --- S3 server access logging target for the CloudTrail destination bucket (environments/security
# only) ----------------------------------------------------------------------------------------
#
# Security Hub S3.9 finding: the CloudTrail destination bucket (aws_s3_bucket.trail) has no server
# access logging. AWS requires the logging destination to be a separate bucket to avoid an infinite
# delivery loop, and — independent of that recommendation — AWS technically PROHIBITS a bucket with
# Object Lock enabled from being used as a server-access-log destination at all, so the CloudTrail
# bucket itself (Object Lock enabled) could never serve as its own target. AWS also documents that
# granting logging.s3.amazonaws.com s3:PutObject is insufficient against an SSE-KMS-encrypted
# destination (the log-delivery service account may not have access to a customer-managed key) —
# this bucket deliberately uses SSE-S3, not the shared cloudtrail-logs KMS key used elsewhere in
# this module. Per AWS's own guidance, this target bucket does not itself need server access
# logging (doing so would create a logging loop) — its own S3.9 finding is expected to be
# suppressed, not remediated.

resource "aws_s3_bucket" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = "${var.name_prefix}-s3-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Application = "cloudtrail"
    Purpose     = "s3-server-access-log-target"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail_access_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3 required for a server-access-log destination — see file header
    }
  }
}

resource "aws_s3_bucket_public_access_block" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.trail_access_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail_access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Deliberately no Object Lock here: AWS explicitly prohibits an Object-Lock-enabled bucket from
# being used as a server-access-log destination — see file header. Lifecycle mirrors the CloudTrail
# destination bucket's own retention convention (1-year-then-Glacier) for consistency across this
# account's logging buckets, rather than inventing a separate retention policy for a lower-value,
# higher-volume log stream.
resource "aws_s3_bucket_lifecycle_configuration" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail_access_logs[0].id

  rule {
    id     = "archive-after-1-year"
    status = "Enabled"

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

data "aws_iam_policy_document" "trail_access_logs_bucket_policy" {
  count = var.create_destination_bucket ? 1 : 0

  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail_access_logs[0].arn}/*"]

    # BucketOwnerEnforced (this bucket's default Object Ownership, same as aws_s3_bucket.trail)
    # disables ACLs, so the legacy log-delivery-group ACL grant is unavailable — this bucket-policy
    # grant, scoped to exactly the CloudTrail destination bucket as source, is the only supported
    # mechanism and matches AWS's own documented current guidance.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.trail[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "trail_access_logs" {
  count = var.create_destination_bucket ? 1 : 0

  bucket = aws_s3_bucket.trail_access_logs[0].id
  policy = data.aws_iam_policy_document.trail_access_logs_bucket_policy[0].json
}

resource "aws_s3_bucket_logging" "trail" {
  count = var.create_destination_bucket ? 1 : 0

  bucket        = aws_s3_bucket.trail[0].id
  target_bucket = aws_s3_bucket.trail_access_logs[0].id
  target_prefix = "${aws_s3_bucket.trail[0].id}/"
}
