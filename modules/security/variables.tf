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

variable "kms_key_arn" {
  description = "Encrypts the security-findings SNS topic — reuses the environment's own cloudtrail-logs key (add \"sns.amazonaws.com\" to its additional_services), no dedicated key for this alone."
  type        = string
}

variable "enable_finding_notifications" {
  description = "Whether to create the EventBridge rules + SNS topic routing GuardDuty (severity >= 4.0, MEDIUM+) and Security Hub (HIGH/CRITICAL, workflow status NEW) findings to a notification topic. Defaults to true in every account, matching enable_guardduty/enable_security_hub's own per-account-not-just-delegated-admin posture — a finding in any account's own detector deserves a notification path, not only aggregated findings in the security account."
  type        = bool
  default     = true
}

variable "finding_notification_emails" {
  description = "Email addresses to subscribe to the security-findings SNS topic. Defaults to empty — this repository does not invent or hardcode a real destination; each address confirms via the SNS confirmation email before receiving anything. See modules/alerting's identical email_subscriptions pattern."
  type        = list(string)
  default     = []
}
