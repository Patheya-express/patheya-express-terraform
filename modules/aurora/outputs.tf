output "cluster_id" {
  value = aws_rds_cluster.this.id
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  value = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Aurora's own load-balanced reader endpoint across every reader instance — null when reader_count = 0."
  value       = var.reader_count > 0 ? aws_rds_cluster.this.reader_endpoint : null
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "database_name" {
  value = aws_rds_cluster.this.database_name
}

output "master_username" {
  value = aws_rds_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = "RDS-managed secret ARN — consumed by External Secrets Operator's ExternalSecret for PgBouncer (modules/eks-addons/pgbouncer.tf)."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "backup_vault_arn" {
  value = aws_backup_vault.primary.arn
}
