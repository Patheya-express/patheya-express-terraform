output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "Cloudflare CNAME target for api.qa.patheyaexpress.com."
  value       = module.alb.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "migration_task_definition_arn" {
  description = "Pass to `aws ecs run-task` — never a service."
  value       = module.ecs.migration_task_definition_arn
}

output "ecr_repository_url" {
  value = module.ecr.repository_urls["api-gateway"]
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_database_url_secret_arn" {
  value = module.rds.database_url_secret_arn
}

output "redis_primary_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "frontend_distribution_domain_names" {
  description = "CloudFront domain per app — the Cloudflare CNAME target for each of var.frontend_domains."
  value       = module.static_site.distribution_domain_names
}

output "frontend_bucket_names" {
  value = module.static_site.bucket_names
}
