variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "private_data_subnet_ids" {
  type = list(string)
}

variable "flow_log_kms_key_arn" {
  description = "From module.kms — encrypts the VPC Flow Logs CloudWatch Logs group."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention for VPC Flow Logs. 30 days in every environment, per platform-standards.md Section 11's \"30 days hot\" logging standard applied to network flow data too."
  type        = number
  default     = 30
}

variable "nlb_allowed_cidrs" {
  description = <<-EOT
    IPv4 CIDR blocks allowed to reach the NLB on 443 — Cloudflare's current published edge IP
    ranges (ADR-004, cloud-architecture-blueprint.md Section 16: Cloudflare is the sole public
    edge, with this NLB as its only origin). Required, no default, and validated non-empty: this
    repository does not hardcode Cloudflare's IP list here, since it changes over time and a stale
    hardcoded copy would be its own liability — the caller (this environment's tfvars, kept
    current the same way the previously-external process did) supplies it.

    Phase 0 remediation: the ingress rule this drives previously accepted 0.0.0.0/0 unconditionally,
    with a comment stating the real restriction was applied by "a scheduled process outside this
    module." That meant the security group's actual, Terraform-managed state was open to the
    entire internet, and any future `apply` — run by anyone, for any unrelated reason — would
    silently revert whatever narrowing that external process had applied. This variable brings the
    restriction fully under Terraform's declarative control instead: the source of truth is one
    place (this variable), not a security group state Terraform declares one way and a separate
    process mutates another way underneath it.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.nlb_allowed_cidrs) > 0
    error_message = "nlb_allowed_cidrs must not be empty — an empty list here would silently create zero ingress rules on 443, not the previous 0.0.0.0/0 baseline. Populate it with Cloudflare's current published IPv4 ranges (https://www.cloudflare.com/ips-v4/) before applying this module for real."
  }

  validation {
    condition     = alltrue([for c in var.nlb_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in nlb_allowed_cidrs must be a valid IPv4 CIDR block (e.g. \"173.245.48.0/20\")."
  }
}
