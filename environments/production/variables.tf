variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "operating_mode" {
  description = <<-EOT
    Production lifecycle state — idle | build | live (docs/production-lifecycle.md). Deliberately
    no default: every plan/apply of this layer must name its mode, set in the committed
    operating-mode.auto.tfvars so a mode change is a reviewed Git change, not a CLI flag.
      idle  — no NAT Gateways, no Tailscale router, no GitHub runner; foundation only.
      build — 3 NAT Gateways (one per AZ), router 1, runner 1.
      live  — same as build for this layer; the eventual full production runtime.
  EOT
  type        = string

  validation {
    condition     = contains(["idle", "build", "live"], var.operating_mode)
    error_message = "operating_mode must be one of: idle, build, live."
  }
}

variable "nlb_allowed_cidrs" {
  description = "Cloudflare's current published IPv4 edge ranges (https://www.cloudflare.com/ips-v4/) — see modules/networking's own variable description for why this isn't hardcoded or defaulted. Required; populate via terraform.tfvars (gitignored) before applying this environment for real."
  type        = list(string)
}

variable "security_finding_notification_emails" {
  description = "Email addresses to subscribe to this account's GuardDuty/Security Hub finding notifications (modules/security's finding_notification_emails). Defaults to empty — this repository does not invent one; populate via terraform.tfvars once a real address or distribution list exists."
  type        = list(string)
  default     = []
}
