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

  tags = merge(var.tags, { Application = "alb", Purpose = "public-load-balancer" })
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
