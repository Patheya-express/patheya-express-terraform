variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "management_account_email" {
  type = string
}

variable "member_accounts" {
  type = map(object({
    email = string
    ou    = string
  }))
}

variable "budget_notification_emails" {
  type = list(string)
}

variable "security_account_id" {
  description = "Filled in AFTER environments/security's first apply creates that account (via this same environments/management run) and you note its ID from the output — used to delegate GuardDuty/Security Hub/CloudTrail administration to it. Left as a separate variable (not derived from module.organizations.member_account_ids at plan time) because that dependency is real and automatic — see main.tf; this variable exists only for the CloudTrail bucket cross-reference, which genuinely needs a second apply pass. See docs/bootstrap-guide.md's deployment order."
  type        = string
}

variable "security_account_cloudtrail_bucket_name" {
  description = "The bucket name environments/security's cloudtrail module output produces — copy in after that environment's first apply. See docs/bootstrap-guide.md."
  type        = string
}

variable "enable_identity_center" {
  type    = bool
  default = false
}

variable "identity_center_group_ids" {
  type    = map(string)
  default = {}
}

variable "security_finding_notification_emails" {
  description = "Email addresses to subscribe to this account's GuardDuty/Security Hub finding notifications (modules/security's finding_notification_emails). Defaults to empty — this repository does not invent one; populate via terraform.tfvars once a real address or distribution list exists."
  type        = list(string)
  default     = []
}
