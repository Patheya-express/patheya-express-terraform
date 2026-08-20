output "guardduty_detector_id" {
  value = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "security_hub_account_id" {
  value = var.enable_security_hub ? aws_securityhub_account.this[0].id : null
}

output "account_analyzer_arn" {
  value = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.account[0].arn : null
}

output "organization_analyzer_arn" {
  value = var.is_delegated_admin_account && var.enable_access_analyzer ? aws_accessanalyzer_analyzer.organization[0].arn : null
}
