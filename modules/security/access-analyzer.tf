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

# Phase 0.5 remediation (Organizations trusted-service-access review): creating an ORGANIZATION-type
# analyzer from a non-management account (this one is created from environments/security, above)
# requires that account to already be registered as the Organizations delegated administrator for
# access-analyzer.amazonaws.com — Access Analyzer, unlike GuardDuty/SecurityHub, has no
# service-specific resource that performs this registration itself. Reuses this module's existing
# delegate_admin_account_id variable (already set only in environments/management, for
# GuardDuty/SecurityHub) rather than introducing a second one — one variable, three delegations.
resource "aws_organizations_delegated_administrator" "access_analyzer" {
  count = var.delegate_admin_account_id != null ? 1 : 0

  account_id        = var.delegate_admin_account_id
  service_principal = "access-analyzer.amazonaws.com"
}
