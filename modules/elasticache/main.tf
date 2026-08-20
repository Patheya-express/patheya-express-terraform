resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.tags, { Application = "elasticache", Purpose = "redis-subnet-group" })
}

# cluster-enabled=yes is the whole point (cloud-architecture-blueprint.md Section 6: "cluster
# mode enabled") — set once here, applied identically across every environment; only shard/
# replica counts vary per environment (variables.tf), never whether cluster mode itself is on.
resource "aws_elasticache_parameter_group" "this" {
  # aws_elasticache_parameter_group has no name_prefix argument (unlike its RDS counterparts) —
  # a literal name is the only option, so create_before_destroy below is what avoids a naming
  # collision on replace instead of a generated suffix.
  name        = "${var.name_prefix}-redis-params"
  family      = "redis7"
  description = "Cluster mode enabled — one parameter group shape for every environment."

  parameter {
    name  = "cluster-enabled"
    value = "yes"
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "redis-parameter-group" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # AWS requires automatic_failover_enabled = true whenever a shard has at least one replica,
  # and rejects it when replicas_per_node_group = 0 (development's single-node shape) — this
  # derives both from the one variable rather than asking the caller to keep two flags in sync.
  ha_enabled = var.replicas_per_shard > 0
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Patheya Express — BullMQ, Socket.IO adapter (Phase 4 app-code follow-up), cache-aside, distributed locks (cloud-architecture-blueprint.md Section 6)."

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type

  num_node_groups         = var.num_shards
  replicas_per_node_group = var.replicas_per_shard

  automatic_failover_enabled = local.ha_enabled
  multi_az_enabled           = local.ha_enabled

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [var.redis_security_group_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  # Transit encryption + AUTH are both mandatory per platform-standards.md Section 13 ("TLS 1.2+
  # in transit everywhere, no exceptions") — see the Phase 4 final report's documented-conflicts
  # section for what this requires of the application's ioredis client, which this phase does not
  # modify (out of scope: "no application changes").
  transit_encryption_enabled = true
  auth_token                 = var.auth_token
  auth_token_update_strategy = "ROTATE"

  snapshot_retention_limit = var.snapshot_retention_days
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  apply_immediately = var.apply_immediately

  tags = merge(var.tags, { Application = "elasticache", Purpose = "primary-cache-and-queue-backend" })
}
