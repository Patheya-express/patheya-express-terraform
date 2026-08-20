variable "aws_region" {
  description = "Primary AWS region — ap-south-1 (Mumbai), per cloud-architecture-blueprint.md Section 2."
  type        = string
  default     = "ap-south-1"
}

variable "account_alias" {
  description = "Short alias for the AWS account this bootstrap runs against, e.g. \"management\", \"dev\", \"staging\", \"prod\". Used in the state bucket name — one bucket per account, per platform-standards.md Section 9."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.account_alias))
    error_message = "account_alias must be lowercase alphanumeric with hyphens only."
  }
}

variable "account_id" {
  description = "The 12-digit AWS account ID this bootstrap runs against — included in the state bucket name for guaranteed global uniqueness without a random suffix (platform-standards.md Section 4)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}
