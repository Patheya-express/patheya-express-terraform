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
  value = module.aurora.master_user_secret_arn
}

output "aurora_cluster_arn" {
  value = module.aurora.cluster_arn
}

output "redis_primary_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "redis_configuration_endpoint" {
  value = module.elasticache.configuration_endpoint
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

output "external_credential_secret_arns" {
  value = module.secrets_manager.external_credential_secret_arns
}

output "alerting_topic_arn" {
  value = module.alerting.topic_arn
}
