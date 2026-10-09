output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Consumed by app/ — the ALB."
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Consumed by app/ — ECS tasks."
  value       = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Consumed by data/ — Aurora, ElastiCache, RDS Proxy."
  value       = module.vpc.private_data_subnet_ids
}

output "aurora_security_group_id" {
  description = "Consumed by data/'s Aurora cluster."
  value       = module.networking.aurora_security_group_id
}

output "redis_security_group_id" {
  description = "Consumed by data/'s ElastiCache replication group — the ECS-topology Redis group (ingress from ECS tasks only)."
  value       = module.networking.redis_ecs_security_group_id
}

output "rds_proxy_security_group_id" {
  description = "Consumed by data/'s RDS Proxy."
  value       = module.networking.rds_proxy_security_group_id
}

output "alb_security_group_id" {
  description = "Consumed by app/'s ALB."
  value       = module.networking.alb_security_group_id
}

output "ecs_task_security_group_id" {
  description = "Consumed by app/'s ECS API/worker services."
  value       = module.networking.ecs_task_security_group_id
}

output "ecs_migration_security_group_id" {
  description = "Consumed by app/ (published as an output for the CI migration run-task)."
  value       = module.networking.ecs_migration_security_group_id
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}

output "permission_boundary_arn" {
  description = "Consumed by data/ and app/ — every Terraform-created role in this account carries it."
  value       = module.iam.permission_boundary_arn
}

output "operating_mode" {
  value = var.operating_mode
}

output "ecs_contract" {
  description = "The ECS resource names the CI deploy role is scoped to — app/ asserts its module outputs match."
  value       = local.ecs_contract
}

output "static_site_bucket_names" {
  description = "The bucket names the frontend deploy role is scoped to — app/ asserts its module outputs match."
  value       = local.static_site_bucket_names
}

output "shared_services_api_gateway_repository_arn" {
  value = local.shared_services_api_gateway_repository_arn
}

output "shared_services_production_dns_role_arn" {
  value = local.shared_services_production_dns_role_arn
}

output "backend_ecs_deploy_role_arn" {
  description = "patheya-express-platform `production` GitHub Environment variable PRODUCTION_ECS_DEPLOY_ROLE_ARN."
  value       = module.iam.backend_ecs_deploy_role_arn
}

output "frontend_static_deploy_role_arn" {
  description = "frontend `production` GitHub Environment variable PRODUCTION_STATIC_DEPLOY_ROLE_ARN."
  value       = module.iam.frontend_static_deploy_role_arn
}

# Retired EKS cluster's persistent control-plane log group (eks-persistent.tf) — kept for its
# retention period as audit evidence; no layer consumes it any more.
output "eks_cluster_log_group_name" {
  value = aws_cloudwatch_log_group.eks_cluster.name
}
