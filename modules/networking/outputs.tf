# --- EKS topology ----------------------------------------------------------------------------------
# null when create_eks_topology_security_groups = false (Production's ECS Fargate runtime).

output "nlb_security_group_id" {
  value = try(aws_security_group.nlb[0].id, null)
}

output "eks_node_security_group_id" {
  value = try(aws_security_group.eks_nodes[0].id, null)
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "redis_security_group_id" {
  value = try(aws_security_group.redis[0].id, null)
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

# --- ECS/ALB topology ------------------------------------------------------------------------------
# null when create_ecs_topology_security_groups = false (the default) — these resources simply
# don't exist in that case.

output "alb_security_group_id" {
  value = try(aws_security_group.alb[0].id, null)
}

output "ecs_task_security_group_id" {
  value = try(aws_security_group.ecs_tasks[0].id, null)
}

output "rds_security_group_id" {
  description = "null unless ecs_database_target = \"rds\"."
  value       = try(aws_security_group.rds[0].id, null)
}

output "redis_ecs_security_group_id" {
  value = try(aws_security_group.redis_ecs[0].id, null)
}

output "rds_proxy_security_group_id" {
  description = "null unless ecs_database_target = \"aurora\". Attached to the RDS Proxy (production/data)."
  value       = try(aws_security_group.rds_proxy[0].id, null)
}

output "ecs_migration_security_group_id" {
  description = "null unless ecs_database_target = \"aurora\". Passed by CI to `aws ecs run-task` for the one-off migration task."
  value       = try(aws_security_group.ecs_migration[0].id, null)
}
