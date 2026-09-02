variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "create_destination_bucket" {
  description = "true when called from environments/security (the log-archive account that owns the trail's S3 destination — separation of duties from the management account that owns the trail resource itself). false when called from environments/management (which only creates the trail, pointing at the security account's already-existing bucket via existing_bucket_name)."
  type        = bool
}

variable "create_trail" {
  description = "true when called from environments/management (org trails can only be created by the management account). false when called from environments/security (which only owns the destination bucket)."
  type        = bool
}

variable "organization_id" {
  description = "Required when create_destination_bucket = true — scopes the bucket policy to this org only."
  type        = string
  default     = null
}

variable "management_account_id" {
  description = "Required when create_destination_bucket = true — the account whose trail is allowed to write here."
  type        = string
  default     = null
}

variable "existing_bucket_name" {
  description = "Required when create_trail = true and create_destination_bucket = false — the security account's bucket name, read via terraform_remote_state from the calling management environment."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "From module.kms's \"cloudtrail-logs\" key — encrypts both the S3 destination (when create_destination_bucket) and the CloudWatch Logs group (when create_trail)."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the real-time trail feed. S3 retention is separate and effectively indefinite (compliance archive) — see main.tf's lifecycle rule."
  type        = number
  default     = 90
}

variable "enable_object_lock" {
  description = <<-EOT
    Enables S3 Object Lock (GOVERNANCE mode) on the destination bucket, when
    create_destination_bucket = true. Object Lock can only be enabled AT BUCKET CREATION —
    AWS provides no supported way to turn it on for an existing bucket after the fact (a support
    request is the only path, and it isn't guaranteed). This module's bucket has never been
    applied to a real AWS account as of this variable's introduction (Phase 0, pre-provisioning),
    so enabling it now costs nothing and closes the finding cleanly; flip this to false only if
    this module's bucket has since been applied for real without Object Lock and this would
    otherwise force a destroy/recreate of the entire log archive.

    GOVERNANCE mode (not COMPLIANCE): a locked object still can't be deleted or overwritten before
    its retention period expires, but a principal with s3:BypassGovernanceRetention can override it
    if genuinely necessary — COMPLIANCE mode's total immutability (unoverridable even by the
    account root user) is a stronger, one-way door this repository leaves for an explicit human
    decision (see object_lock_retention_days's description) rather than defaulting into.
  EOT
  type        = bool
  default     = true
}

variable "object_lock_retention_days" {
  description = "Object Lock GOVERNANCE-mode retention period, in days, for every object written to the destination bucket. Defaults to 400 — safely past the 365-day point main.tf's lifecycle rule transitions objects to Glacier, so a still-locked object survives that transition rather than becoming unlocked right as it moves to cold storage. Only meaningful when enable_object_lock = true."
  type        = number
  default     = 400
}
