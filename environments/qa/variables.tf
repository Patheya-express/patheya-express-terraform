variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "security_finding_notification_emails" {
  description = "Email addresses to subscribe to this account's GuardDuty/Security Hub finding notifications (modules/security's finding_notification_emails). Defaults to empty — this repository does not invent one; populate via terraform.tfvars once a real address or distribution list exists."
  type        = list(string)
  default     = []
}
