variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "dr_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "app_db_username" {
  description = "Runtime application PostgreSQL role (DML only, via RDS Proxy). Created by docs/production-database-bootstrap.md — must match exactly."
  type        = string
  default     = "patheya_app"
}

variable "migrator_db_username" {
  description = "Schema-owning PostgreSQL role used only by the migration task. Created by docs/production-database-bootstrap.md — must match exactly."
  type        = string
  default     = "patheya_migrator"
}

variable "alert_email_subscriptions" {
  description = "Email addresses (an on-call distribution list, typically) to subscribe to this environment's database/cache CloudWatch alarms. Defaults to empty — see modules/alerting's email_subscriptions variable. Populate via terraform.tfvars once a real address exists; this repository does not invent one."
  type        = list(string)
  default     = []
}
