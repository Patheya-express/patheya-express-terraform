output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Consumed by Phase 4's Aurora/ElastiCache subnet groups."
  value       = module.vpc.private_data_subnet_ids
}

output "eks_node_security_group_id" {
  description = "Consumed by Phase 3's EKS node group configuration."
  value       = module.networking.eks_node_security_group_id
}

output "aurora_security_group_id" {
  description = "Consumed by Phase 4's Aurora cluster."
  value       = module.networking.aurora_security_group_id
}

output "redis_security_group_id" {
  description = "Consumed by Phase 4's ElastiCache replication group."
  value       = module.networking.redis_security_group_id
}

output "cloudtrail_logs_kms_key_arn" {
  description = "Consumed by the account root's module.config and module.security (Phase 1D.2 split) — the same key, read from here rather than each creating their own."
  value       = module.kms.key_arns["cloudtrail-logs"]
}
