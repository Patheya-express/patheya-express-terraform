output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "For the apex zone: give these to the domain registrar. For a delegated subdomain zone: give these to the apex zone's owning environment to create the NS delegation record — see environments/shared-services/route53-delegation.tf."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  value = var.create_wildcard_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : null
}
