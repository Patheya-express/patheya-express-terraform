variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "dr_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "alert_email_subscriptions" {
  description = "Email addresses (an on-call distribution list, typically) to subscribe to this environment's database/cache CloudWatch alarms. Defaults to empty — see modules/alerting's email_subscriptions variable. Populate via terraform.tfvars once a real address exists; this repository does not invent one."
  type        = list(string)
  default     = []
}
