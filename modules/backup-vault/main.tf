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
