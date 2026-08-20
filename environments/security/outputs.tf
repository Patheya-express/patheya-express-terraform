output "cloudtrail_bucket_name" {
  description = "Copy into environments/management's `security_account_cloudtrail_bucket_name` variable."
  value       = module.cloudtrail.bucket_name
}

output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}
