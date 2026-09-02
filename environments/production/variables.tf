variable "aws_region" {
  type    = string
  default = "ap-south-1"
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
