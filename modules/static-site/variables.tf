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
  description = "CloudFront price class. \"PriceClass_100\" (North America + Europe edge locations only) is the lowest-cost option — appropriate for a temporary DEV+QA audience, not a global production audience. Production uses \"PriceClass_200\", the lowest class that includes India edge locations."
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

variable "security_headers" {
  description = <<-EOT
    Response headers added to every response from every distribution (one shared CloudFront
    response headers policy). Defaults are safe for any SPA; the caller supplies the CSP.
      hsts_max_age_seconds      — Strict-Transport-Security max-age. includeSubDomains and preload
                                  are deliberately off: each site opts in for its own host only.
      referrer_policy           — CloudFront referrer-policy enum value.
      frame_option              — DENY or SAMEORIGIN.
      permissions_policy        — Permissions-Policy header value; null omits it.
      content_security_policy   — CSP value; null omits it.
      csp_report_only           — true sends it as Content-Security-Policy-Report-Only (logged by
                                  the browser, never enforced) so a policy can be verified before
                                  it can break the application.
  EOT
  type = object({
    hsts_max_age_seconds    = optional(number, 31536000)
    referrer_policy         = optional(string, "strict-origin-when-cross-origin")
    frame_option            = optional(string, "DENY")
    permissions_policy      = optional(string)
    content_security_policy = optional(string)
    csp_report_only         = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["DENY", "SAMEORIGIN"], var.security_headers.frame_option)
    error_message = "security_headers.frame_option must be DENY or SAMEORIGIN."
  }
}
