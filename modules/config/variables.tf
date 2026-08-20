variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  description = "From module.kms's \"cloudtrail-logs\" key (config snapshots are the same sensitivity class — reused rather than provisioning a fifth near-identical key)."
  type        = string
}

variable "create_aggregator" {
  description = "true only in environments/security — creates an organization-wide Config Aggregator so compliance status across every account is visible from one place."
  type        = bool
  default     = false
}

variable "organization_id" {
  description = "Required when create_aggregator = true."
  type        = string
  default     = null
}

variable "mandatory_tag_keys" {
  description = "The fourteen mandatory tag keys from platform-standards.md Section 5 — enforced here via AWS Config's required-tags managed rule, the concrete mechanism behind that document's \"Reject any resource missing mandatory tags\" requirement (this task's Section 11)."
  type        = list(string)
  default = [
    "Environment", "Project", "Owner", "ManagedBy", "CostCenter", "Repository",
    "Application", "Version", "Confidentiality", "BusinessUnit", "Compliance",
    "Retention", "CreatedBy", "Purpose",
  ]
}
