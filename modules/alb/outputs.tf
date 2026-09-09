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
