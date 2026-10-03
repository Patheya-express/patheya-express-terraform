variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "name_suffix" {
  description = "Distinguishes this web ACL within the account, e.g. \"api-alb\" -> patheya-production-api-alb."
  type        = string
}

variable "description" {
  type    = string
  default = "Baseline AWS managed-rule protection for an internet-facing ALB."
}

variable "managed_rule_groups" {
  description = <<-EOT
    AWS-managed rule groups, evaluated in ascending priority order.
      count_only       — true runs the whole group in COUNT mode (observe, never block).
      count_rule_names — individual rules inside the group overridden to COUNT.

    Defaults are AWS's general-purpose baseline for an API:
      AmazonIpReputationList  — known-malicious source IPs (botnets, scanners).
      CommonRuleSet           — OWASP-style protections. SizeRestrictions_BODY is overridden to
                                COUNT: it blocks any body over 8 KB, and the API accepts multipart
                                document uploads (delivery DocumentsController).
      KnownBadInputsRuleSet   — exploit payloads (Log4Shell, Java deserialization, etc.).
      SQLiRuleSet             — SQL-injection patterns.
    AnonymousIpList and BotControl are deliberately not defaults: the first blocks legitimate users
    on VPNs/privacy relays, the second is paid and needs per-endpoint tuning.
  EOT
  type = list(object({
    name             = string
    priority         = number
    count_only       = optional(bool, false)
    count_rule_names = optional(list(string), [])
  }))
  default = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10 },
    { name = "AWSManagedRulesCommonRuleSet", priority = 20, count_rule_names = ["SizeRestrictions_BODY"] },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30 },
    { name = "AWSManagedRulesSQLiRuleSet", priority = 40 },
  ]

  validation {
    condition     = length(distinct([for g in var.managed_rule_groups : g.priority])) == length(var.managed_rule_groups)
    error_message = "Every managed rule group needs a unique priority."
  }
}

variable "sampled_requests_enabled" {
  description = "Keeps a sample of matching requests viewable in the WAF console."
  type        = bool
  default     = true
}

variable "logging_enabled" {
  description = "Sends web ACL logs to a dedicated CloudWatch Logs group (aws-waf-logs-*)."
  type        = bool
  default     = true
}

variable "log_only_non_allowed_requests" {
  description = "true (default) logs only BLOCK/COUNT decisions — the actionable signal — instead of every allowed request, which would mostly duplicate ALB access logs at CloudWatch ingestion cost."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "log_kms_key_arn" {
  description = "Optional CMK for the WAF log group. The key policy must allow logs.<region>.amazonaws.com."
  type        = string
  default     = null
}
