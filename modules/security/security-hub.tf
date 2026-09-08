resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = false # explicit standards subscriptions below instead — no silent "whatever AWS defaults to today"
}

resource "aws_securityhub_standards_subscription" "foundational" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:ap-south-1::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:ap-south-1::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.this]
}

# Management account only.
resource "aws_securityhub_organization_admin_account" "this" {
  count = var.delegate_admin_account_id != null ? 1 : 0

  admin_account_id = var.delegate_admin_account_id
}

# Security account only (as delegated admin).
resource "aws_securityhub_organization_configuration" "this" {
  count = var.is_delegated_admin_account && var.enable_security_hub ? 1 : 0

  auto_enable           = true
  auto_enable_standards = "NONE" # standards are subscribed explicitly above, not auto-selected by AWS
  organization_configuration {
    configuration_type = "CENTRAL" # Security Hub's central configuration — one place to manage standards/controls for every member account, rather than each account configuring its own
  }

  depends_on = [aws_securityhub_organization_admin_account.this]
}
