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
  default     = []

  validation {
    condition     = !var.create_eks_topology_security_groups || length(var.nlb_allowed_cidrs) > 0
    error_message = "nlb_allowed_cidrs must not be empty while create_eks_topology_security_groups = true — an empty list here would silently create zero ingress rules on 443, not the previous 0.0.0.0/0 baseline. Populate it with Cloudflare's current published IPv4 ranges (https://www.cloudflare.com/ips-v4/) before applying this module for real."
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
    IPv4 CIDR blocks allowed to reach the ALB on 443 — either Cloudflare's current published edge
    IP ranges (https://www.cloudflare.com/ips-v4/) where Cloudflare fronts the ALB
    (development-temp), or ["0.0.0.0/0"] where the ALB is itself the public, AWS WAF-protected
    edge (Production, ADR-004 as amended). Required and validated non-empty only when
    create_ecs_topology_security_groups = true; this repository does not hardcode Cloudflare's IP
    list, since it changes over time, and the caller supplies the current list.
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

variable "create_eks_topology_security_groups" {
  description = <<-EOT
    true (default) creates the EKS-oriented NLB, EKS-node and EKS-fronted Redis security groups
    and every rule referencing them — every existing caller's plan is unchanged (moved blocks in
    security-groups.tf turn the count gating into a pure state move). false omits them all, for
    an environment with no EKS cluster (Production's ECS Fargate runtime). The aurora security
    group is never gated: it is attached to the Aurora cluster itself.
  EOT
  type        = bool
  default     = true
}

variable "ecs_database_target" {
  description = <<-EOT
    Which PostgreSQL topology the ECS task security groups are wired to (only meaningful with
    create_ecs_topology_security_groups = true):
      "rds"    (default) — standalone RDS (modules/rds): creates the rds security group, with
               ECS tasks -> RDS on 5432. development-temp's existing shape, unchanged.
      "aurora" — Aurora behind RDS Proxy: creates rds_proxy and ecs_migration security groups;
               API/worker tasks -> RDS Proxy -> Aurora, and a one-off migration task -> Aurora
               writer directly. No standalone RDS group is created.
  EOT
  type        = string
  default     = "rds"

  validation {
    condition     = contains(["rds", "aurora"], var.ecs_database_target)
    error_message = "ecs_database_target must be \"rds\" or \"aurora\"."
  }
}

variable "alb_http_redirect_ingress" {
  description = "true additionally admits port 80 from var.alb_allowed_cidrs to the ALB, solely so modules/alb's HTTP -> HTTPS redirect listener is reachable. false (default) keeps the ALB 443-only — development-temp's existing shape."
  type        = bool
  default     = false
}

variable "ecs_api_container_port" {
  description = "The API container's listening port — the ALB target group's forwarded port and the ECS task security group's ingress port from the ALB."
  type        = number
  default     = 3000
}
