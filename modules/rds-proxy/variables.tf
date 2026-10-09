variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "db_cluster_identifier" {
  description = "From module.aurora's cluster_id."
  type        = string
}

variable "subnet_ids" {
  description = "Private-data subnets — the proxy lives beside the database it fronts."
  type        = list(string)
}

variable "security_group_id" {
  description = "From module.networking's rds_proxy_security_group_id (ecs_database_target = \"aurora\")."
  type        = string
}

variable "auth_secret_arn" {
  description = "Secrets Manager secret holding the runtime application user as {\"username\": ..., \"password\": ...} — the only identity this proxy accepts."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key encrypting var.auth_secret_arn."
  type        = string
}

variable "permission_boundary_arn" {
  description = "This account's permission boundary (modules/iam) — every Terraform-created role carries it."
  type        = string
}

variable "idle_client_timeout_seconds" {
  type    = number
  default = 1800
}

variable "max_connections_percent" {
  type    = number
  default = 80

  validation {
    condition     = var.max_connections_percent >= 1 && var.max_connections_percent <= 100
    error_message = "max_connections_percent must be between 1 and 100."
  }
}

variable "max_idle_connections_percent" {
  type    = number
  default = 40
}

variable "connection_borrow_timeout_seconds" {
  type    = number
  default = 120
}
