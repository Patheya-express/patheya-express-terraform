resource "aws_accessanalyzer_analyzer" "account" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-account-analyzer"
  type          = "ACCOUNT"

  tags = merge(var.tags, { Application = "security", Purpose = "iam-access-analyzer-account" })
}

# Security account only — one organization-wide analyzer instead of an account-scoped one, so an
# external-access finding (a resource policy granting access outside the org) is caught regardless
# of which account it appears in.
resource "aws_accessanalyzer_analyzer" "organization" {
  count = var.is_delegated_admin_account && var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-organization-analyzer"
  type          = "ORGANIZATION"

  tags = merge(var.tags, { Application = "security", Purpose = "iam-access-analyzer-organization" })
}
