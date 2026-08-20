variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_cidr" {
  description = "e.g. 10.30.0.0/16 for production — see cloud-architecture-blueprint.md Section 2 for the per-environment CIDR allocation (non-overlapping across environments, peerable if ever needed)."
  type        = string
}

variable "availability_zones" {
  description = "Exactly 3 AZs — cloud-architecture-blueprint.md Section 2 requires 3 for EKS control-plane HA and topologySpreadConstraints to spread pods meaningfully."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "Exactly 3 Availability Zones are required (cloud-architecture-blueprint.md Section 2)."
  }
}

variable "public_subnet_cidrs" {
  description = "One /24 per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "Exactly 3 public subnet CIDRs are required, one per AZ."
  }
}

variable "private_app_subnet_cidrs" {
  description = "One /20 per AZ, same order as availability_zones — sized for EKS worker node + pod IP density."
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_cidrs) == 3
    error_message = "Exactly 3 private application subnet CIDRs are required, one per AZ."
  }
}

variable "private_data_subnet_cidrs" {
  description = "One /24 per AZ, same order as availability_zones — Aurora/ElastiCache only."
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnet_cidrs) == 3
    error_message = "Exactly 3 private data subnet CIDRs are required, one per AZ."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    false (default, and the only acceptable value in production) provisions one NAT Gateway per
    AZ, per cloud-architecture-blueprint.md Section 2 — keeps a single-AZ NAT failure's blast
    radius to one AZ's egress only. true collapses to a single shared NAT Gateway, a deliberate
    cost tradeoff acceptable in development/staging only (platform-standards.md Section 6 — every
    environment is the same *shape*, but scale/cost tradeoffs like this one are exactly what's
    allowed to differ).
  EOT
  type        = bool
  default     = false
}
