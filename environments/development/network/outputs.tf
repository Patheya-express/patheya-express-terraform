output "vpc_id" {
  value = try(module.vpc[0].vpc_id, null)
}

output "vpc_cidr" {
  value = try(module.vpc[0].vpc_cidr, null)
}

output "public_subnet_ids" {
  value = try(module.vpc[0].public_subnet_ids, null)
}

output "private_app_subnet_ids" {
  value = try(module.vpc[0].private_app_subnet_ids, null)
}

output "private_data_subnet_ids" {
  description = "Consumed by Phase 4's Aurora/ElastiCache subnet groups."
  value       = try(module.vpc[0].private_data_subnet_ids, null)
}

output "eks_node_security_group_id" {
  description = "Consumed by Phase 3's EKS node group configuration."
  value       = try(module.networking[0].eks_node_security_group_id, null)
}

output "aurora_security_group_id" {
  description = "Consumed by Phase 4's Aurora cluster."
  value       = try(module.networking[0].aurora_security_group_id, null)
}

output "redis_security_group_id" {
  description = "Consumed by Phase 4's ElastiCache replication group."
  value       = try(module.networking[0].redis_security_group_id, null)
}
