variable "environment" {
  description = "Environment/account name — one of the seven accounts in cloud-architecture-blueprint.md Section 2. Drives the name_prefix output and the Environment tag."
  type        = string

  validation {
    condition = contains(
      ["management", "security", "shared-services", "development", "qa", "staging", "production", "dr"],
      var.environment
    )
    error_message = "environment must be one of: management, security, shared-services, development, qa, staging, production, dr (cloud-architecture-blueprint.md Section 2, extended for the QA account added in Phase 1B)."
  }
}

variable "application" {
  description = "The specific application/component this resource serves, e.g. \"api-gateway\", \"vpc\", or \"platform\" for shared infrastructure with no single owning app."
  type        = string
}

variable "owner" {
  description = "Team accountable for the resource (platform-standards.md Section 5)."
  type        = string
  default     = "platform-engineering"
}

variable "cost_center" {
  description = "Cost center tag value, feeds chargeback (platform-standards.md Section 20)."
  type        = string
  default     = "eng-platform"
}

variable "repository" {
  description = "Repository where this resource's IaC definition lives."
  type        = string
  default     = "patheya-express-terraform"
}

variable "resource_version" {
  description = "Version of the application currently deployed by/with this resource, where applicable. \"n/a\" for infrastructure with no independent version (matches platform-standards.md's example)."
  type        = string
  default     = "n/a"
}

variable "confidentiality" {
  description = "One of: public, internal, confidential, restricted (platform-standards.md Section 5)."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.confidentiality)
    error_message = "confidentiality must be one of: public, internal, confidential, restricted."
  }
}

variable "business_unit" {
  description = "Business unit for multi-BU cost allocation."
  type        = string
  default     = "engineering"
}

variable "compliance" {
  description = "Compliance classification, e.g. \"pci-adjacent\" for anything in the payment data path. \"none\" where genuinely not applicable."
  type        = string
  default     = "none"
}

variable "retention" {
  description = "Retention period matching what's actually configured on the resource (e.g. \"35-days\"), not aspirational."
  type        = string
}

variable "purpose" {
  description = "One-line human-readable description of what this resource is for."
  type        = string
}

variable "tags_extra" {
  description = "Additional tags merged on top of the mandatory fourteen — never used to override one of the mandatory keys (a duplicate key here is a bug in the caller, not a supported override mechanism)."
  type        = map(string)
  default     = {}
}
