variable "tags" {
  type = map(string)
}

variable "repository_names" {
  description = "One ECR repository per app, matching platform-standards.md Section 4's naming: patheya-express/<app>. Backend's api-gateway and worker share one image/repository (docs/infrastructure/workers.md in the backend repo) — do not add a separate \"worker\" repository."
  type        = list(string)
  default = [
    "api-gateway",
    "customer-app",
    "partner-app",
    "delivery-app",
    "admin-app",
  ]
}

variable "kms_key_arn" {
  description = "From module.kms's \"ecr\" key."
  type        = string
}

variable "organization_id" {
  description = "AWS Organization ID (from module.organizations, read via remote state in the shared-services environment) — scopes the cross-account pull repository policy to org members only, never public or account-enumerable access."
  type        = string
}

variable "untagged_image_expiry_days" {
  description = "Untagged images (superseded digests from a retag, or an aborted push) expire after this many days — tagged images are never auto-expired by this policy, only removed by an explicit image-count-based rule below."
  type        = number
  default     = 7
}

variable "keep_last_n_tagged_images" {
  description = "Retains only the N most recent tagged images per repository — bounds storage growth over years of daily releases without an explicit age cutoff that could delete a rarely-deployed-but-still-valid old release tag."
  type        = number
  default     = 30
}
