output "bucket_names" {
  value = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  value = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "distribution_ids" {
  value = { for k, v in aws_cloudfront_distribution.this : k => v.id }
}

output "distribution_domain_names" {
  description = "CloudFront's own *.cloudfront.net domain per site — the Cloudflare CNAME target for each site's configured domain in var.sites."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.domain_name }
}
