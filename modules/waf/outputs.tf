output "web_acl_arn" {
  description = "Pass to modules/alb's web_acl_arn."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  value = aws_wafv2_web_acl.this.name
}

output "log_group_name" {
  value = try(aws_cloudwatch_log_group.this[0].name, null)
}
