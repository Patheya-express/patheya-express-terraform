variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "apex_zone_id" {
  description = "From environments/shared-services's `apex_zone_id` output — a cross-account value, so (consistent with Phase 2's established stance) supplied as a tfvar rather than a cross-account terraform_remote_state read. See docs/bootstrap-guide.md (Phase 2) for why cross-account remote state reads were avoided throughout this repository."
  type        = string
}

variable "apex_certificate_arn" {
  description = "From environments/shared-services's `apex_certificate_arn` output."
  type        = string
}

variable "ecr_registry_host" {
  description = "From environments/shared-services's ecr_repository_urls output — cross-account, supplied as a tfvar, same pattern as apex_zone_id/apex_certificate_arn above. See modules/supply-chain-security's variable of the same name."
  type        = string
}

variable "operating_mode" {
  description = "build | live — see docs/production-lifecycle.md. build: no data layer is read and PgBouncer/data-backed ExternalSecrets are omitted; live: requires the data layer applied first. No idle value (this layer is destroyed in idle). Deliberately no default; set in the committed operating-mode.auto.tfvars."
  type        = string

  validation {
    condition     = contains(["build", "live"], var.operating_mode)
    error_message = "operating_mode must be build or live for the platform layer — idle means this layer is destroyed, not applied."
  }
}
