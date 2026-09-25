# Single-instance RDS PostgreSQL — the temporary-DEV+QA counterpart to modules/aurora, not a
# replacement for it. Deliberately does NOT use manage_master_user_password (contrast with
# modules/aurora/main.tf): that mechanism produces an RDS-managed secret containing discrete JSON
# fields (username/password/host/port), which is exactly right for Production's Kubernetes/
# External Secrets Operator path (modules/eks-addons/external-secrets.tf composes DATABASE_URL
# from those fields via a Go template at the Kubernetes layer) but is the wrong shape for ECS:
# ECS's native `secrets` task-definition injection maps one Secrets Manager field to one
# environment variable — it cannot compose several fields into the single DATABASE_URL string the
# application actually reads (apps/api-gateway/src/config/env.validation.ts requires one URI-
# shaped env var), and the application is explicitly not being changed to read discrete
# DB_HOST/DB_USER/DB_PASSWORD variables instead.
#
# This module therefore generates its own master password (random_password, the same pattern
# modules/secrets-manager already uses for the ElastiCache AUTH token) and, once the instance
# exists and its endpoint is known, composes the complete DATABASE_URL itself into one dedicated
# Secrets Manager secret — directly ECS-injectable as a single environment variable, with no
# runtime composition step required anywhere.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-rds"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.tags, { Application = "rds", Purpose = "rds-subnet-group" })
}

# force_ssl=1 — server-side enforcement matching modules/aurora's identical parameter, so a stray
# non-TLS connection attempt fails closed rather than silently succeeding unencrypted. The
# application's DATABASE_URL carries sslmode=require independently (client-side); this is the
# server-side half.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name_prefix}-rds-"
  family      = "postgres16"
  description = "force_ssl enforcement - the standalone-RDS counterpart to modules/aurora's cluster parameter group."

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, { Application = "rds", Purpose = "rds-parameter-group" })

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache AUTH token constraints don't apply here (this is the RDS/Postgres master password,
# not Redis AUTH) — RDS's own constraint set is: 8-128 printable ASCII characters, excluding
# "/", '"', "@", and space.
#
# Pinned to "!$&*()-_=+" (a proper subset of RDS's full allowed special-character set, not a
# protocol-compliance issue either way) because this is the value the live development-temp
# database's master password was actually generated under (confirmed against a prior
# terraform plan artifact and this account's Secrets Manager write history) — this module has
# only one caller (environments/development-temp), and that database is live and actively
# serving traffic. A wider override_special here would force-replace random_password.master and
# silently rotate the live RDS master password on the next apply, with no coordinated
# ECS service redeploy to pick up the new credential. Revisit only alongside a deliberate,
# coordinated password-rotation change, not as an incidental side effect of a module edit.
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!$&*()-_=+"
}

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-rds"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az            = false # single-AZ — temporary DEV+QA only; Production HA remains modules/aurora's Multi-AZ writer+reader
  publicly_accessible = false

  # aws_db_instance (single-instance RDS) names these arguments backup_window/maintenance_window
  # — NOT preferred_backup_window/preferred_maintenance_window, which are aws_rds_cluster's
  # (Aurora's) argument names. This module's own variables keep the preferred_* names since those
  # are just this module's input identifiers, not resource arguments.
  backup_retention_period = var.backup_retention_days
  backup_window           = var.preferred_backup_window
  maintenance_window      = var.preferred_maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  apply_immediately         = var.apply_immediately
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-rds-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? var.kms_key_arn : null

  monitoring_interval = var.monitoring_interval_seconds
  monitoring_role_arn = var.monitoring_interval_seconds > 0 ? aws_iam_role.monitoring[0].arn : null

  tags = merge(var.tags, { Application = "rds", Purpose = "primary-database" })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
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

  name               = "${var.name_prefix}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json

  tags = merge(var.tags, { Application = "rds", Purpose = "enhanced-monitoring-role" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval_seconds > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_partition" "current" {}

# --- DATABASE_URL secret ------------------------------------------------------------------------
# Composed entirely from values Terraform already knows (the instance's own address/port/db_name
# plus the random_password generated above) — no data-source round-trip against an
# AWS-managed secret, no runtime composition step. This is the one dedicated secret ECS's
# `secrets` task-definition block points DATABASE_URL at.

resource "aws_secretsmanager_secret" "database_url" {
  name        = "patheya-express/${var.environment}/database-url"
  description = "Complete DATABASE_URL connection string for ${var.name_prefix}-rds — generated and composed entirely by Terraform, never by a runtime process. See modules/rds/main.tf for why this diverges from modules/aurora's manage_master_user_password approach."
  kms_key_id  = var.kms_key_arn

  tags = merge(var.tags, { Application = "rds", Purpose = "database-url" })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${var.master_username}:${random_password.master.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.database_name}?sslmode=require"
}
