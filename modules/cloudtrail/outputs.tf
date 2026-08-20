output "bucket_name" {
  value = var.create_destination_bucket ? aws_s3_bucket.trail[0].id : null
}

output "bucket_arn" {
  value = var.create_destination_bucket ? aws_s3_bucket.trail[0].arn : null
}

output "trail_arn" {
  value = var.create_trail ? aws_cloudtrail.organization[0].arn : null
}

output "log_group_name" {
  value = var.create_trail ? aws_cloudwatch_log_group.trail[0].name : null
}
