output "route53_zone_id" {
  value = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Copy into environments/shared-services's `development_zone_name_servers` variable."
  value       = module.route53.name_servers
}

output "acm_certificate_arn" {
  value = module.route53.certificate_arn
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}

output "cloudtrail_logs_kms_key_arn" {
  description = "The cloudtrail-logs key this root owns since the KMS ownership move. environments/development/network does not read this output - it resolves the same existing key for VPC Flow Logs encryption via data \"aws_kms_alias\" (alias/patheya-development-cloudtrail-logs)."
  value       = module.kms.key_arns["cloudtrail-logs"]
}
