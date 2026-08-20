variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  description = "development | staging | production — used only in the secret naming path, not for conditional logic."
  type        = string
}

variable "kms_key_arn" {
  description = "Encrypts every secret this module creates — reuses the same customer-managed key the calling environment's Aurora/ElastiCache resources use, not a separate secrets-only key (one CMK per data class, per platform-standards.md Section 4 — Secrets Manager here is storage for the database/cache data class's credentials, not its own data class)."
  type        = string
}

variable "external_credential_secrets" {
  description = <<-EOT
    Names (not values) of external SaaS credential secrets to provision empty containers for —
    e.g. ["jwt-signing-key", "cloudinary", "razorpay", "smtp"]. This module creates the
    aws_secretsmanager_secret resource (name, KMS key, tags) only; it never writes a
    aws_secretsmanager_secret_version, because this module has no legitimate source for a real
    third-party API key or JWT signing secret — those are populated once, out-of-band, by a
    human with the actual credential (see docs/secrets-guide.md), the same way Phase 1A's
    secret.env.example was always a placeholder for a human to fill in, never a generated value.
  EOT
  type        = list(string)
  default     = []
}
