resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-aurora"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.tags, { Application = "aurora", Purpose = "aurora-subnet-group" })
}

# force_ssl=1 (cloud-architecture-blueprint.md Section 5) — every client connection, including
# PgBouncer's own connection to the writer/reader endpoints, must present TLS. Prisma's
# DATABASE_URL already carries sslmode=require independently (a client-side setting); this is the
# server-side enforcement that makes a stray non-TLS connection attempt fail closed rather than
# silently succeed unencrypted.
resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.name_prefix}-aurora-cluster-"
  family      = "aurora-postgresql16"
  description = "Cluster-level parameters — force_ssl and log_min_duration_statement for slow-query logging (this task's Section 9)."

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # milliseconds — logs any query slower than 1s; matches docs/aurora-guide.md's slow-query-logging section
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "aurora-cluster-parameter-group" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name_prefix}-aurora-instance-"
  family      = "aurora-postgresql16"
  description = "Instance-level parameters."

  tags = merge(var.tags, { Application = "aurora", Purpose = "aurora-instance-parameter-group" })

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval_seconds > 0 ? 1 : 0

  name               = "${var.name_prefix}-aurora-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json

  tags = merge(var.tags, { Application = "aurora", Purpose = "enhanced-monitoring-role" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval_seconds > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_partition" "current" {}

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name_prefix}-aurora"

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned" # Serverless v2 is a provisioned-engine-mode instance class ("db.serverless"), not the legacy engine_mode = "serverless"

  database_name   = var.database_name
  master_username = var.master_username
  # RDS-managed master credential: RDS creates, stores, and rotates this secret in Secrets
  # Manager itself — no random_password/aws_secretsmanager_secret_version anywhere in this
  # module or its caller (cloud-architecture-blueprint.md Section 11, platform-standards.md
  # Section 13's "Aurora credentials — Secrets Manager's native rotation" requirement, satisfied
  # natively rather than hand-built).
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection = var.deletion_protection
  apply_immediately   = var.apply_immediately
  # Terraform-only lifecycle (platform-standards.md Section 1, principle 4/5) — a manual final
  # snapshot flag would let an operator skip it interactively; instead every environment always
  # takes one, named deterministically so a destroy is traceable to exactly one snapshot.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-aurora-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless ? [1] : []
    content {
      min_capacity = var.serverless_min_acu
      max_capacity = var.serverless_max_acu
    }
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "primary-database" })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

locals {
  # 1 writer + var.reader_count readers, one per AZ. Writer is always index 0 — Aurora's own
  # failover priority (tier) defaults to 0 for the first instance created and increments for
  # each subsequent one unless explicitly overridden, which already gives the writer the highest
  # promotion priority without this module needing to set failover_priority by hand.
  instance_count = 1 + var.reader_count
}

resource "aws_rds_cluster_instance" "this" {
  count = local.instance_count

  cluster_identifier = aws_rds_cluster.this.id
  identifier         = count.index == 0 ? "${var.name_prefix}-aurora-writer" : "${var.name_prefix}-aurora-reader-${count.index}"

  engine         = aws_rds_cluster.this.engine
  engine_version = aws_rds_cluster.this.engine_version

  instance_class = var.serverless ? "db.serverless" : (count.index == 0 ? var.instance_class_writer : var.instance_class_reader)

  db_parameter_group_name = aws_db_parameter_group.this.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null

  monitoring_interval = var.monitoring_interval_seconds
  monitoring_role_arn = var.monitoring_interval_seconds > 0 ? aws_iam_role.monitoring[0].arn : null

  publicly_accessible = false
  apply_immediately   = var.apply_immediately

  tags = merge(var.tags, {
    Application = "aurora",
    Purpose     = count.index == 0 ? "aurora-writer-instance" : "aurora-reader-instance"
  })
}

# Automatic 30-day rotation of the RDS-managed master secret — AWS's own rotation function
# (no Lambda authored or deployed by this module; RDS-managed secrets use an AWS-owned rotation
# mechanism, not a customer Lambda), satisfying platform-standards.md Section 13's "Aurora
# credentials — Secrets Manager's native rotation Lambda, 30-day cycle" without this module
# provisioning any Lambda itself.
resource "aws_secretsmanager_secret_rotation" "master_user" {
  secret_id = aws_rds_cluster.this.master_user_secret[0].secret_arn

  rotation_rules {
    automatically_after_days = 30
  }
}
