data "aws_caller_identity" "current" {}

# One Origin Access Control, reused by every distribution below — OAC is a signing configuration,
# not a per-distribution resource; each bucket's policy still scopes access to its own specific
# distribution only (see aws_s3_bucket_policy below), so sharing this resource does not grant any
# distribution access to another site's bucket.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name_prefix}-static-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket" "this" {
  for_each = var.sites

  # S3 bucket names are globally unique across ALL of AWS, not just this account — the account ID
  # suffix (this repository's existing convention, e.g. patheya-management-config-106940013632)
  # guarantees no collision, including against a future real environments/development in a
  # different account that might otherwise compute the identical name_prefix-based bucket name.
  bucket = "${var.name_prefix}-${each.key}-frontend-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Application = "static-site", Purpose = "${each.key}-frontend-origin" })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.sites

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.sites

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.sites

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled" # cheap insurance against a bad deploy overwriting the previous known-good build
  }
}

# Bucket policy scoped to exactly one distribution's ARN via aws:SourceArn — never a public bucket
# policy, never open to every CloudFront distribution in the account.
data "aws_iam_policy_document" "bucket_policy" {
  for_each = var.sites

  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this[each.key].arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = var.sites

  bucket = aws_s3_bucket.this[each.key].id
  policy = data.aws_iam_policy_document.bucket_policy[each.key].json
}

resource "aws_cloudfront_distribution" "this" {
  for_each = var.sites

  enabled             = true
  comment             = "${var.name_prefix}-${each.key}-frontend"
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = [each.value]

  origin {
    domain_name              = aws_s3_bucket.this[each.key].bucket_regional_domain_name
    origin_id                = "${each.key}-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${each.key}-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Managed cache policy "CachingOptimized" — long-lived caching by default; per-object
    # Cache-Control headers set at upload time (immutable for hashed assets, no-store for
    # index.html) still take precedence, matching the existing nginx behavior this replaces.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # SPA fallback — every deep link is a real Angular Router path with nothing server-side to
  # resolve it (confirmed: apps/*/src/app/app.config.ts use standard PathLocationStrategy, no
  # HashLocationStrategy anywhere). A direct navigation or refresh on such a path returns S3's own
  # 403 (private bucket, no such key) or 404, both rewritten to index.html with a 200 so the
  # Angular app itself resolves the route client-side — the exact behavior the existing nginx
  # `try_files ... /index.html` / vercel.json rewrite already provide.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(var.tags, { Application = "static-site", Purpose = "${each.key}-frontend-distribution" })
}
