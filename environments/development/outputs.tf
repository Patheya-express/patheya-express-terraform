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
  description = "Consumed by environments/development/network's own module.networking (VPC Flow Logs encryption) via terraform_remote_state - the reverse of the read this root used to do against network before the KMS ownership move."
  value       = module.kms.key_arns["cloudtrail-logs"]
}
