resource "aws_route53_zone" "this" {
  name = var.zone_name

  tags = merge(var.tags, {
    Name        = var.zone_name
    Application = "route53"
    Purpose     = "hosted-zone-${var.zone_name}"
  })
}

resource "aws_acm_certificate" "this" {
  count = var.create_wildcard_certificate ? 1 : 0

  domain_name               = var.zone_name
  subject_alternative_names = ["*.${var.zone_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Application = "route53"
    Purpose     = "acm-certificate-${var.zone_name}"
  })
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.create_wildcard_certificate ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = var.create_wildcard_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
