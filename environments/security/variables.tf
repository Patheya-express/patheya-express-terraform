variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "organization_id" {
  description = "From environments/management's `organization_id` output — copy in after that environment's first apply."
  type        = string
}

variable "management_account_id" {
  type = string
}

variable "security_finding_notification_emails" {
  description = "Email addresses to subscribe to this account's org-wide GuardDuty/Security Hub finding notifications (modules/security's finding_notification_emails). Defaults to empty — this repository does not invent one; populate via terraform.tfvars once a real address or distribution list exists."
  type        = list(string)
  default     = []
}
