variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "operating_mode" {
  description = <<-EOT
    Production lifecycle state — idle | build | live (docs/production-lifecycle.md). Deliberately
    no default: every plan/apply of this layer must name its mode, set in the committed
    operating-mode.auto.tfvars so a mode change is a reviewed Git change, not a CLI flag.
      idle  — no NAT Gateways, no Tailscale router; foundation only.
      build — 3 NAT Gateways (one per AZ), router 1.
      live  — same as build for this layer; the eventual full production runtime.
  EOT
  type        = string

  validation {
    condition     = contains(["idle", "build", "live"], var.operating_mode)
    error_message = "operating_mode must be one of: idle, build, live."
  }
}

variable "shared_services_account_id" {
  description = "Owns the api-gateway ECR repository and the apex Route53 zone (environments/shared-services). Used only to construct those two deterministic ARNs for this layer's IAM scoping."
  type        = string
  default     = "668506406019"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be a 12-digit AWS account ID."
  }
}

variable "static_sites" {
  description = "Static web apps served from S3 + CloudFront by the app layer (modules/static-site keys). Must match environments/production/app's var.static_sites — the frontend deploy role is scoped to exactly these buckets."
  type        = list(string)
  default     = ["admin", "customer", "restaurant", "delivery"]
}

variable "security_finding_notification_emails" {
  description = "Email addresses to subscribe to this account's GuardDuty/Security Hub finding notifications (modules/security's finding_notification_emails). Defaults to empty — this repository does not invent one; populate via terraform.tfvars once a real address or distribution list exists."
  type        = list(string)
  default     = []
}
