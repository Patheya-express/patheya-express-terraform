output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "apex_zone_id" {
  value = module.route53_apex.zone_id
}

output "apex_zone_name_servers" {
  description = "Give these to the domain registrar for patheyaexpress.com."
  value       = module.route53_apex.name_servers
}

output "apex_certificate_arn" {
  value = module.route53_apex.certificate_arn
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}
