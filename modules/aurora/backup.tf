# AWS Backup — a second, independent recovery path from Aurora's own automated backups
# (main.tf's backup_retention_days), per cloud-architecture-blueprint.md Section 12: "nightly
# snapshot copy to the DR account as a second, independent recovery path that doesn't depend on
# Global Database replication staying healthy" (Global Database itself isn't provisioned until
# DR moves to warm-standby — Section 12 — so this module's job today is exactly the nightly
# snapshot copy leg, standing on its own).

resource "aws_backup_vault" "primary" {
  name        = "${var.name_prefix}-aurora-vault"
  kms_key_arn = var.kms_key_arn

  tags = merge(var.tags, { Application = "aurora", Purpose = "backup-vault-primary" })
}

# Phase 0 remediation: opt-in, disabled by default — see enable_vault_lock's description.
resource "aws_backup_vault_lock_configuration" "primary" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name = aws_backup_vault.primary.name

  changeable_for_days = var.vault_lock_changeable_for_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name_prefix}-aurora-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = merge(var.tags, { Application = "aurora", Purpose = "backup-service-role" })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "this" {
  name = "${var.name_prefix}-aurora-backup-plan"

  rule {
    rule_name         = "nightly"
    target_vault_name = aws_backup_vault.primary.name
    # Preferred backup window (main.tf) is Aurora's own automated-backup window; AWS Backup runs
    # independently, scheduled a little later so both never contend for I/O headroom at once.
    schedule = "cron(0 19 * * ? *)" # 19:00 UTC = 00:30 IST

    lifecycle {
      delete_after = var.backup_retention_days
    }

    copy_action {
      destination_vault_arn = var.dr_backup_vault_arn

      lifecycle {
        delete_after = var.backup_retention_days
      }
    }
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "backup-plan" })
}

resource "aws_backup_selection" "this" {
  name         = "${var.name_prefix}-aurora-backup-selection"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [aws_rds_cluster.this.arn]
}
