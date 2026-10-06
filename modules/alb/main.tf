# Internet-facing ALB — "internet-facing" in AWS's sense (has public IPs, resolves via public DNS)
# but real public reach is restricted entirely by the security group this module attaches to
# (var.alb_security_group_id, scoped to Cloudflare's published ranges only in module.networking) —
# consistent with the existing NLB's identical posture elsewhere in this repository.

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  idle_timeout               = var.idle_timeout_seconds
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.access_logs[0].id
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, { Application = "alb", Purpose = "public-load-balancer" })

  # The bucket policy must exist before ELB validates write access when access logging is enabled.
  depends_on = [aws_s3_bucket_policy.access_logs]
}

# --- Access logs (var.access_logs_enabled) -----------------------------------------------------------
# ELB access-log delivery supports only SSE-S3 (AES256) on the destination bucket — not SSE-KMS —
# so this bucket deliberately does not take a KMS key. Private, owner-enforced, TLS-only, expiring.

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

resource "aws_s3_bucket" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = "${var.name_prefix}-alb-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Application = "alb", Purpose = "alb-access-logs" })
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  # The regional Elastic Load Balancing account (data.aws_elb_service_account) — the delivery
  # principal for regions launched before August 2022, which includes ap-south-1.
  statement {
    sid       = "AllowElbAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/${var.access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs[0].arn, "${aws_s3_bucket.access_logs[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

# --- AWS WAF (var.web_acl_arn) ------------------------------------------------------------------------

resource "aws_wafv2_web_acl_association" "this" {
  # Gated on the plan-time-known flag, not on web_acl_arn: the ARN is unknown at plan time when the
  # web ACL is created in the same apply, which Terraform cannot use in count.
  count = var.web_acl_enabled ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn

  lifecycle {
    precondition {
      condition     = var.web_acl_arn != null
      error_message = "web_acl_enabled is true but web_acl_arn is null."
    }
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-api-tg"
  vpc_id      = var.vpc_id
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip" # required for Fargate awsvpc-mode tasks

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = var.health_check_interval_seconds
    timeout             = var.health_check_timeout_seconds
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
  }

  # No stickiness block — disabled by design. The application's Socket.IO Redis adapter already
  # fans events out across instances, so round-robin distribution (the ALB default) is correct;
  # sticky sessions would be an unnecessary constraint, not a requirement.

  deregistration_delay = 30

  tags = merge(var.tags, { Application = "alb", Purpose = "api-target-group" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# HTTP -> HTTPS redirect, per the approved architecture's Cloudflare-HTTPS-only edge — Cloudflare
# itself is expected to talk to this origin over HTTPS already, but a plain-HTTP request that
# somehow arrives is redirected rather than served in the clear.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
