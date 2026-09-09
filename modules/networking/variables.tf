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

# --- ECS/ALB topology (Phase 2, temporary DEV+QA) -----------------------------------------------
# Additive only: gated behind create_ecs_topology_security_groups (default false), so every
# existing caller of this module (development/staging/production, none of which pass this
# variable today) gets byte-for-byte the same plan as before this addition. Distinct resource
# names (alb/ecs_tasks/rds/redis_ecs, not aurora/redis) — this is a parallel, ECS-fronted
# topology for a standalone RDS instance and a non-EKS Redis, not a repurposing of the
# EKS-oriented aurora/redis security groups above, which remain completely untouched.

variable "create_ecs_topology_security_groups" {
  description = "false (default) creates none of the ALB/ECS-task/RDS/Redis-for-ECS security groups below — every existing caller's plan is unaffected. true additionally creates them, for an ECS Fargate-based environment (e.g. environments/development-temp) that has no EKS nodes at all."
  type        = bool
  default     = false
}

variable "alb_allowed_cidrs" {
  description = <<-EOT
    IPv4 CIDR blocks allowed to reach the ALB on 443 — Cloudflare's current published edge IP
    ranges (https://www.cloudflare.com/ips-v4/), the ECS/ALB counterpart to nlb_allowed_cidrs
    above. Required and validated non-empty only when create_ecs_topology_security_groups = true;
    the same rationale as nlb_allowed_cidrs applies verbatim — this repository does not hardcode
    Cloudflare's IP list, since it changes over time, and the caller (this environment's tfvars)
    supplies the current list.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.alb_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in alb_allowed_cidrs must be a valid IPv4 CIDR block (e.g. \"173.245.48.0/20\")."
  }

  validation {
    condition     = !var.create_ecs_topology_security_groups || length(var.alb_allowed_cidrs) > 0
    error_message = "alb_allowed_cidrs must not be empty when create_ecs_topology_security_groups = true — an empty list would create zero ingress rules on 443, not a 0.0.0.0/0 fallback. Populate it with Cloudflare's current published IPv4 ranges before applying."
  }
}

variable "ecs_api_container_port" {
  description = "The API container's listening port — the ALB target group's forwarded port and the ECS task security group's ingress port from the ALB."
  type        = number
  default     = 3000
}
