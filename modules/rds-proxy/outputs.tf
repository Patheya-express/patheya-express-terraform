output "endpoint" {
  description = "Read/write proxy endpoint — the host in the runtime DATABASE_URL."
  value       = aws_db_proxy.this.endpoint
}

output "proxy_name" {
  value = aws_db_proxy.this.name
}

output "proxy_arn" {
  value = aws_db_proxy.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
