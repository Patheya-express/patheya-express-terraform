# Static web — admin (primary web app) and the customer/restaurant/delivery web builds (secondary
# channels; the Capacitor mobile apps are primary and call the API directly, never through
# CloudFront). Private S3 origins behind CloudFront with Origin Access Control and SPA fallback,
# via the existing modules/static-site — no nginx containers in Production.

# --- ACM (us-east-1, CloudFront) ------------------------------------------------------------------

resource "aws_acm_certificate" "web" {
  provider = aws.us_east_1

  domain_name               = local.site_domains["admin"]
  subject_alternative_names = [for site, domain in local.site_domains : domain if site != "admin"]
  validation_method         = "DNS"

  tags = merge(module.shared.tags, { Application = "acm", Purpose = "static-web-cloudfront-certificate" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "web_certificate_validation" {
  provider = aws.dns
  for_each = {
    for dvo in aws_acm_certificate.web.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "web" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.web.arn
  validation_record_fqdns = [for record in aws_route53_record.web_certificate_validation : record.fqdn]
}

# --- S3 + CloudFront ---------------------------------------------------------------------------------

module "static_site" {
  source = "../../../modules/static-site"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  sites               = local.site_domains
  acm_certificate_arn = aws_acm_certificate_validation.web.certificate_arn
  price_class         = "PriceClass_200" # lowest class that includes India edge locations

  # SSE-S3: build artifacts are public by nature once served; OAC + a private bucket policy are the
  # access control, and SSE-KMS would additionally require a CloudFront grant on the key.
  kms_key_arn = null
}

resource "aws_route53_record" "web" {
  provider = aws.dns
  for_each = local.site_domains

  zone_id = data.aws_route53_zone.apex.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = module.static_site.distribution_domain_names[each.key]
    zone_id                = module.static_site.distribution_hosted_zone_ids[each.key]
    evaluate_target_health = false
  }
}

# The frontend deploy role (root layer) is scoped to these exact bucket names.
check "static_site_buckets_match_root_deploy_role_scope" {
  assert {
    condition     = toset(values(module.static_site.bucket_names)) == toset(local.network.static_site_bucket_names)
    error_message = "Static-site bucket names no longer match the root layer's static_site_bucket_names — the frontend deploy role would be denied. Align var.static_sites in both layers."
  }
}
