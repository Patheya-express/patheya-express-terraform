output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "api_service_name" {
  value = aws_ecs_service.api.name
}

output "worker_service_name" {
  value = aws_ecs_service.worker.name
}

output "migration_task_definition_arn" {
  description = "Pass to `aws ecs run-task` (CI or manual) — this is intentionally never a service."
  value       = aws_ecs_task_definition.migration.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "api_task_role_arn" {
  value = aws_iam_role.api_task.arn
}

output "worker_task_role_arn" {
  value = aws_iam_role.worker_task.arn
}

output "migration_task_role_arn" {
  value = aws_iam_role.migration_task.arn
}

output "api_log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}

output "worker_log_group_name" {
  value = aws_cloudwatch_log_group.worker.name
}

output "migration_log_group_name" {
  value = aws_cloudwatch_log_group.migration.name
}
