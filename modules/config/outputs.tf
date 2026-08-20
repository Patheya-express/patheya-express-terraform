output "recorder_name" {
  value = aws_config_configuration_recorder.this.name
}

output "bucket_name" {
  value = aws_s3_bucket.config.id
}

output "aggregator_arn" {
  value = var.create_aggregator ? aws_config_configuration_aggregator.organization[0].arn : null
}
