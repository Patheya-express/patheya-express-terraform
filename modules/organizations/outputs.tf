output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "organization_arn" {
  value = aws_organizations_organization.this.arn
}

output "root_id" {
  value = aws_organizations_organization.this.roots[0].id
}

output "ou_ids" {
  description = "Organizational Unit IDs, keyed by name (security, infrastructure, workloads)."
  value       = local.ou_ids
}

output "member_account_ids" {
  description = "Member account IDs, keyed by account alias — consumed by every environment's provider `assume_role` block and by the iam module's cross-account trust policies."
  value       = { for k, v in aws_organizations_account.member : k => v.id }
}

output "member_account_arns" {
  value = { for k, v in aws_organizations_account.member : k => v.arn }
}
