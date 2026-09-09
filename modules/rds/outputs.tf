output "db_instance_identifier" {
  value = aws_db_instance.this.identifier
}

output "endpoint" {
  description = "Host only (no port) — aws_db_instance.address, not the combined host:port .endpoint attribute, so callers that need just the hostname (e.g. security-group documentation, monitoring) don't have to split a string."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "database_url_secret_arn" {
  description = "The complete DATABASE_URL secret's ARN — the only value ECS task definitions need to reference via `secrets` injection. The secret's own value is never exposed as a Terraform output."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "security_group_id_in_use" {
  description = "Echoes back the security group ID this instance was attached to (var.security_group_id) — a convenience for callers wiring dependency order, not a new resource."
  value       = var.security_group_id
}
