output "organization_id" {
  value = module.organizations.organization_id
}

output "member_account_ids" {
  value = module.organizations.member_account_ids
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}
