variable "tags" {
  type = map(string)
}

variable "name" {
  description = "Full vault name, e.g. patheya-development-aurora-vault-dr."
  type        = string
}

variable "kms_key_arn" {
  description = "A KMS key in the SAME region this module's aws provider is configured for — KMS keys are region-scoped, so this cannot be the primary region's key when this module is called with a DR-region provider alias."
  type        = string
}

variable "enable_vault_lock" {
  description = <<-EOT
    Enables AWS Backup Vault Lock on this vault. Disabled by default.

    Vault Lock is a one-way door: once its changeable_for_days cooling-off period passes, the lock
    (and the minimum/maximum retention it enforces) cannot be loosened or removed by anyone,
    including the account root user — only tightened, ever again. That's the entire point (it's
    what actually protects backups from a compromised-or-malicious operator, which a deletable lock
    would not), but it means turning it on is a decision this repository leaves to an explicit,
    per-environment human choice rather than a default every vault silently inherits.
  EOT
  type        = bool
  default     = false
}

variable "vault_lock_changeable_for_days" {
  description = "Cooling-off period (days) during which the lock configuration can still be deleted entirely before becoming permanent. AWS's own minimum is 3 days; defaults to 3 here as the shortest deliberate-decision window — not a suggestion to cut it close. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = 3
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention Vault Lock will enforce — every backup rule targeting this vault must already retain backups at least this long, or the lock configuration itself fails to apply. Null (no minimum enforced) until a human sets one deliberately. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = null
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention Vault Lock will enforce — optional upper bound. Null (no maximum) by default. Only meaningful when enable_vault_lock = true."
  type        = number
  default     = null
}
