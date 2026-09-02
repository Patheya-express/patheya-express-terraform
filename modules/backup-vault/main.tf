# A single-resource module rather than a raw aws_backup_vault block inline in an environment's
# data/main.tf — platform-standards.md Section 9: "an environment directory only calls modules...
# it never defines a raw AWS resource directly." Exists specifically so the DR-region vault
# (created with a provider = aws.dr override at the call site) doesn't become the one exception
# to that rule.
resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = var.kms_key_arn

  tags = merge(var.tags, { Application = "backup-vault", Purpose = var.name })
}

# Phase 0 remediation: opt-in, disabled by default — see enable_vault_lock's description for why
# this isn't defaulted on.
resource "aws_backup_vault_lock_configuration" "this" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name

  changeable_for_days = var.vault_lock_changeable_for_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}
