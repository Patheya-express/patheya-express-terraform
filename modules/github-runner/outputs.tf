output "security_group_id" {
  value = aws_security_group.this.id
}

output "github_pat_secret_arn" {
  description = "Populate this secret's value out-of-band before the runner can register - see main.tf's comment on aws_secretsmanager_secret.github_pat."
  value       = aws_secretsmanager_secret.github_pat.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
