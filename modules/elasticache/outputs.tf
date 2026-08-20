output "replication_group_id" {
  value = aws_elasticache_replication_group.this.replication_group_id
}

output "configuration_endpoint" {
  description = "Cluster-mode configuration endpoint — the single endpoint a cluster-mode-aware client (ioredis with `cluster: true`) connects to; it discovers shards itself. Null when num_shards = 1, since AWS only publishes a configuration_endpoint for genuinely multi-shard replication groups."
  value       = var.num_shards > 1 ? aws_elasticache_replication_group.this.configuration_endpoint_address : null
}

output "primary_endpoint" {
  description = "Single-shard primary endpoint — used when num_shards = 1 (development/staging today), since no configuration_endpoint is published for a 1-shard replication group."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  value = local.ha_enabled ? aws_elasticache_replication_group.this.reader_endpoint_address : null
}

output "port" {
  value = aws_elasticache_replication_group.this.port
}
