variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  description = "development | staging | production."
  type        = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

variable "vpc_id" {
  type = string
}

variable "private_data_subnet_ids" {
  description = "From module.vpc (Phase 2) — the subnets with no default route (cloud-architecture-blueprint.md Section 2)."
  type        = list(string)
}

variable "aurora_security_group_id" {
  description = "From module.networking (Phase 2) — already scoped to 5432 from eks-node-sg only."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed key encrypting storage, Performance Insights, and the RDS-managed master secret (one CMK per data class, platform-standards.md Section 4 — this environment's \"aurora\" key)."
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version — matches the Prisma schema's Postgres 16 target (cloud-architecture-blueprint.md Section 5)."
  type        = string
  default     = "16.4"
}

variable "database_name" {
  description = "Initial database created inside the cluster. Matches the existing schema.prisma's expected database — see docs/aurora-guide.md for how this reconciles with an existing dev/staging database name if one already exists outside Terraform."
  type        = string
  default     = "patheya_express"
}

variable "master_username" {
  description = "RDS-managed master user (var.serverless or not) — the actual credential is never a Terraform value; see manage_master_user_password in main.tf."
  type        = string
  default     = "patheya_admin"
}

variable "serverless" {
  description = "true for development/staging (Aurora Serverless v2, scales toward zero between test runs) — false for production (provisioned db.r6g instances), per cloud-architecture-blueprint.md Section 5's instance-class table."
  type        = bool
}

variable "serverless_min_acu" {
  type    = number
  default = 0.5
}

variable "serverless_max_acu" {
  type    = number
  default = 4
}

variable "instance_class_writer" {
  description = "Ignored when var.serverless is true. Production default per the blueprint's table."
  type        = string
  default     = "db.r6g.xlarge"
}

variable "instance_class_reader" {
  description = "Ignored when var.serverless is true."
  type        = string
  default     = "db.r6g.large"
}

variable "reader_count" {
  description = "Number of reader instances, one per AZ up to the blueprint's \"1 writer + 2 readers\" production topology. 0 is valid for development (writer-only, no read scaling need at that tier)."
  type        = number
  default     = 1

  validation {
    condition     = var.reader_count >= 0 && var.reader_count <= 2
    error_message = "reader_count must be between 0 and 2 — cloud-architecture-blueprint.md Section 5 never specifies more than 2 readers at any documented growth tier."
  }
}

variable "backup_retention_days" {
  description = "Aurora's automated backup retention (PITR window). 35 (the maximum) in production per the blueprint; shorter elsewhere has no operational value (platform-standards.md Section 14's cost-optimization note)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "performance_insights_enabled" {
  type    = bool
  default = true
}

variable "performance_insights_retention_days" {
  description = "7 (free tier) or 731 (2 years, paid). Production uses the paid tier for real incident-postmortem lookback; dev/staging use the free tier."
  type        = number
  default     = 7
}

variable "monitoring_interval_seconds" {
  description = "Enhanced Monitoring granularity. 0 disables it. 15s in production for real incident diagnosis; 60s (or 0) elsewhere is sufficient."
  type        = number
  default     = 60
}

variable "apply_immediately" {
  description = "false in production — changes apply during the next maintenance window instead of immediately, avoiding an unplanned mid-day failover (platform-standards.md Section 1, principle 3)."
  type        = bool
  default     = false
}

variable "preferred_backup_window" {
  type    = string
  default = "17:00-18:00" # 22:30-23:30 IST — outside the blueprint's stated peak order-throughput hours
}

variable "preferred_maintenance_window" {
  type    = string
  default = "sun:18:00-sun:19:00" # 23:30-00:30 IST Sunday
}

variable "alarm_sns_topic_arn" {
  description = "From module.alerting. Alarms still evaluate and appear in CloudWatch with this unset, but notify no one — always pass this."
  type        = string
}

variable "dr_backup_vault_arn" {
  description = <<-EOT
    ARN of an AWS Backup vault in the DR region (ap-southeast-1), created by this same module's
    consumer via the aws.dr provider alias. Cross-REGION backup copy only — cross-ACCOUNT copy to
    the eventual patheya-dr account (cloud-architecture-blueprint.md Section 2's account table) is
    explicitly deferred until that account exists; see docs/backup-guide.md and the Phase 4 final
    report's documented-conflicts section for why.
  EOT
  type        = string
}

variable "enable_vault_lock" {
  description = <<-EOT
    Enables AWS Backup Vault Lock on the primary (this region's) backup vault. Disabled by default
    — see modules/backup-vault's identical variable for why this is a deliberate, per-environment
    human decision rather than a default: once its cooling-off period passes, the lock cannot be
    loosened or removed by anyone, including the account root user. Applying the same optional
    capability to both the primary vault (here) and the DR-region copy (modules/backup-vault)
    keeps them consistent — locking one while leaving the other unprotected would be a confusing,
    partial fix to the same audit finding.
  EOT
  type        = bool
  default     = false
}

variable "vault_lock_changeable_for_days" {
  description = "Cooling-off period (days) before the lock becomes permanent. AWS's minimum is 3. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = 3
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention Vault Lock enforces on this vault. Null (no minimum) until set deliberately. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = null
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention Vault Lock enforces on this vault. Null (no maximum) by default. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = null
}
