output "key_arns" {
  description = "KMS key ARNs, keyed by data class (e.g. \"cloudtrail-logs\", \"ecr\")."
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}

output "key_ids" {
  value = { for k, v in aws_kms_key.this : k => v.key_id }
}

output "alias_arns" {
  value = { for k, v in aws_kms_alias.this : k => v.arn }
}
