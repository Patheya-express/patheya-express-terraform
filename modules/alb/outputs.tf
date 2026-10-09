output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "For a future Route53/DNS alias record, if ever needed — this environment's DNS is expected to be a Cloudflare CNAME to alb_dns_name instead."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "api_target_group_arn_suffix" {
  description = "With alb_arn_suffix, forms the ALBRequestCountPerTarget resource label (\"<alb_arn_suffix>/<api_target_group_arn_suffix>\") for request-based ECS autoscaling."
  value       = aws_lb_target_group.api.arn_suffix
}

output "access_logs_bucket_name" {
  value = try(aws_s3_bucket.access_logs[0].id, null)
}
