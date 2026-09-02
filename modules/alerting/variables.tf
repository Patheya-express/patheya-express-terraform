variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  description = "Encrypts the SNS topic at rest — reuses the environment's own KMS key, no dedicated alerting key."
  type        = string
}

variable "topic_name" {
  description = "Suffix appended to name_prefix — e.g. \"alerts-database\" produces patheya-<env>-alerts-database (platform-standards.md Section 4's SNS naming pattern)."
  type        = string
}

variable "email_subscriptions" {
  description = <<-EOT
    Email addresses to subscribe to this topic (e.g. an on-call distribution list). Each address
    receives an SNS confirmation email and must confirm before it starts receiving alarms.

    Defaults to an empty list — this repository does not invent or hardcode a real destination
    address. Phase 0 remediation: this topic previously had zero subscribers by construction (no
    mechanism to add one existed at all), so every CloudWatch alarm that publishes here — Aurora's
    and ElastiCache's — notified no one. The mechanism now exists; populate this variable via the
    calling environment's tfvars once a real address or distribution list exists.
  EOT
  type        = list(string)
  default     = []
}
