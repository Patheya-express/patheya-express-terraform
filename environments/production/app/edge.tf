# Public API edge — ADR-004 as amended: the ALB is the public entry point for the mobile apps and
# web apps (https://api.patheyaexpress.com), protected by AWS WAF; no Cloudflare in front.
#
# The apex zone lives in shared-services; it is looked up (not hard-coded) through the scoped
# aws.dns provider, which can write only Production's own records.

data "aws_route53_zone" "apex" {
  provider = aws.dns

  name         = var.apex_domain
  private_zone = false
}

# --- ACM (ap-south-1, ALB) ------------------------------------------------------------------------

resource "aws_acm_certificate" "api" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  tags = merge(module.shared.tags, { Application = "acm", Purpose = "api-alb-certificate" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_certificate_validation" {
  provider = aws.dns
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.apex.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_certificate_validation : record.fqdn]
}

# --- WAF -------------------------------------------------------------------------------------------

module "waf" {
  source = "../../../modules/waf"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  name_suffix = "api-alb"
  description = "Production API ALB - AWS managed baseline rule groups, no rate limits, no geo-blocking."

  logging_enabled = true
  log_kms_key_arn = module.kms.key_arns["application"]
}

# --- ALB -------------------------------------------------------------------------------------------

module "alb" {
  source = "../../../modules/alb"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                = local.network.vpc_id
  public_subnet_ids     = local.network.public_subnet_ids
  alb_security_group_id = local.network.alb_security_group_id
  certificate_arn       = aws_acm_certificate_validation.api.certificate_arn

  # Module defaults kept deliberately: target port 3000, /api/v1/health/ready health check,
  # 300s idle timeout (long-lived Socket.IO websockets), ELBSecurityPolicy-TLS13-1-2-2021-06,
  # HTTP -> HTTPS redirect, no stickiness (Redis adapter + websocket-only clients).
  enable_deletion_protection = true
  access_logs_enabled        = true
  web_acl_arn                = module.waf.web_acl_arn

  alarm_sns_topic_arn = module.alerting.topic_arn
}

# --- DNS -------------------------------------------------------------------------------------------

resource "aws_route53_record" "api" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.apex.zone_id
  name    = local.api_domain
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
