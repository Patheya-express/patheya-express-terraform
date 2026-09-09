variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "sites" {
  description = <<-EOT
    Map of app key to its public domain name — one private S3 bucket + one CloudFront
    distribution per entry. Domain names are taken from the frontend repository's own existing
    Kubernetes-overlay convention (customer/restaurant/admin/delivery.patheyaexpress.com for
    production, staging.<app>.patheyaexpress.com for staging), extended with a "qa." tier for
    this temporary environment — never invented ahead of what the application repository already
    expects. No default: the caller supplies the real domain names.
  EOT
  type        = map(string)
}

variable "acm_certificate_arn" {
  description = <<-EOT
    ACM certificate ARN for CloudFront's aliases — MUST be requested in us-east-1 regardless of
    this repository's primary region (ap-south-1); this is a hard CloudFront constraint, not a
    choice. A single certificate covering all var.sites domains (e.g. a *.qa.patheyaexpress.com
    wildcard, or a SAN certificate listing each domain) is expected, reused across every
    distribution this module creates. This module does NOT request or validate a certificate
    itself — an invented certificate is exactly the kind of silent decision this module must not
    make.
  EOT
  type        = string
}

variable "price_class" {
  description = "CloudFront price class. \"PriceClass_100\" (North America + Europe edge locations only) is the lowest-cost option — appropriate for a temporary DEV+QA audience, not a global production audience."
  type        = string
  default     = "PriceClass_100"
}

variable "default_root_object" {
  type    = string
  default = "index.html"
}

variable "kms_key_arn" {
  description = "Optional SSE-KMS key for the S3 buckets. Frontend build artifacts are not sensitive data (unlike DB/secrets), so SSE-S3 (leave this null) is an acceptable, simpler default; pass a key only if the caller wants CMK encryption here too."
  type        = string
  default     = null
}
