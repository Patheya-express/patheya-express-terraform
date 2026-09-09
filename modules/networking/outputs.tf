output "nlb_security_group_id" {
  value = aws_security_group.nlb.id
}

output "eks_node_security_group_id" {
  value = aws_security_group.eks_nodes.id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

# --- ECS/ALB topology (Phase 2, temporary DEV+QA) -----------------------------------------------
# null when create_ecs_topology_security_groups = false (the default, and every existing caller's
# current behavior) — these resources simply don't exist in that case.

output "alb_security_group_id" {
  value = try(aws_security_group.alb[0].id, null)
}

output "ecs_task_security_group_id" {
  value = try(aws_security_group.ecs_tasks[0].id, null)
}

output "rds_security_group_id" {
  value = try(aws_security_group.rds[0].id, null)
}

output "redis_ecs_security_group_id" {
  value = try(aws_security_group.redis_ecs[0].id, null)
}
