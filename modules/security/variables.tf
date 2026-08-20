variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "enable_guardduty" {
  description = "Enabled in every account, including this one when called from environments/security — GuardDuty's own detector is always per-account regardless of delegation."
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  type    = bool
  default = true
}

variable "enable_access_analyzer" {
  type    = bool
  default = true
}

variable "delegate_admin_account_id" {
  description = "Set only in environments/management — the security account's ID, designated as the GuardDuty/Security Hub delegated administrator for the whole organization. Left null everywhere else (delegation is a one-time, management-account-only action)."
  type        = string
  default     = null
}

variable "is_delegated_admin_account" {
  description = "true only in environments/security — enables organization-wide auto-enrollment (every current and future member account automatically gets GuardDuty/Security Hub enabled, no per-account opt-in needed) and creates the organization-scoped Access Analyzer."
  type        = bool
  default     = false
}

variable "organization_id" {
  description = "Required when is_delegated_admin_account = true (Access Analyzer's organization-type analyzer)."
  type        = string
  default     = null
}
