output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_app_subnet_ids" {
  value = module.vpc.private_app_subnet_ids
}

output "eks_node_security_group_id" {
  value = module.networking.eks_node_security_group_id
}

output "private_data_subnet_ids" {
  description = "Consumed by Phase 4's Aurora/ElastiCache subnet groups."
  value       = module.vpc.private_data_subnet_ids
}

output "aurora_security_group_id" {
  description = "Consumed by Phase 4's Aurora cluster."
  value       = module.networking.aurora_security_group_id
}

output "redis_security_group_id" {
  description = "Consumed by Phase 4's ElastiCache replication group."
  value       = module.networking.redis_security_group_id
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}
