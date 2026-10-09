# Consumed by environments/production/app via terraform_remote_state. Secret ARNs only — no
# credential, password or URL value is ever an output.

output "aurora_writer_endpoint" {
  value = module.aurora.writer_endpoint
}

output "aurora_reader_endpoint" {
  value = module.aurora.reader_endpoint
}

output "aurora_port" {
  value = module.aurora.port
}

output "aurora_database_name" {
  value = module.aurora.database_name
}

output "aurora_master_secret_arn" {
  description = "RDS-managed master credential — used only by the one-time bootstrap (docs/production-database-bootstrap.md), never by an application task."
  value       = module.aurora.master_user_secret_arn
}

output "aurora_cluster_arn" {
  value = module.aurora.cluster_arn
}

output "rds_proxy_endpoint" {
  value = module.rds_proxy.endpoint
}

output "rds_proxy_name" {
  value = module.rds_proxy.proxy_name
}

output "database_url_secret_arn" {
  description = "Runtime DATABASE_URL (application user via RDS Proxy) — API/worker tasks."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "database_migration_url_secret_arn" {
  description = "Migration DATABASE_URL (migrator user, direct to the writer) — migration task only."
  value       = aws_secretsmanager_secret.database_migration_url.arn
}

output "app_db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.app_db_credentials.arn
}

output "migrator_db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.migrator_db_credentials.arn
}

output "redis_primary_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "redis_reader_endpoint" {
  value = module.elasticache.reader_endpoint
}

output "redis_port" {
  value = module.elasticache.port
}

output "redis_auth_token_secret_arn" {
  value = module.secrets_manager.redis_auth_token_secret_arn
}

output "secrets_path_prefix" {
  value = module.secrets_manager.secrets_path_prefix
}

output "secrets_kms_key_arn" {
  description = "Encrypts every patheya-express/production/* secret — the ECS execution role needs kms:Decrypt on it."
  value       = module.kms.key_arns["secrets"]
}

output "external_credential_secret_arns" {
  value = module.secrets_manager.external_credential_secret_arns
}

output "alerting_topic_arn" {
  value = module.alerting.topic_arn
}
