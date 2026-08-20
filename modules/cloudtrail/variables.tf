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
