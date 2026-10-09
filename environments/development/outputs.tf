output "terraform_role_arn" {
  value = module.iam.terraform_role_arn
}

output "cloudtrail_logs_kms_key_arn" {
  description = "The cloudtrail-logs key this root owns since the KMS ownership move. environments/development/network does not read this output - it resolves the same existing key for VPC Flow Logs encryption via data \"aws_kms_alias\" (alias/patheya-development-cloudtrail-logs)."
  value       = module.kms.key_arns["cloudtrail-logs"]
}
