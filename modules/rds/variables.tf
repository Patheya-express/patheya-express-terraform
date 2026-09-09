variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "engine_version" {
  description = "PostgreSQL major.minor version. 16.x to match the application's Prisma schema target (the same target modules/aurora's engine_version documents)."
  type        = string
  default     = "16.15"
}

variable "instance_class" {
  description = "Single-instance RDS (no Aurora) — a small burstable class for temporary DEV+QA. Not intended for production use; production remains modules/aurora, unchanged by this module's existence."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial gp3 storage, GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling, GB. Set equal to allocated_storage_gb to disable autoscaling growth beyond the initial size, or higher to allow gradual growth without a manual resize."
  type        = number
  default     = 100
}

variable "database_name" {
  type    = string
  default = "patheya_express"
}

variable "master_username" {
  description = "Master username. The master password is never a variable — it is generated internally via random_password (see main.tf) and never appears in any .tfvars file or Terraform variable."
  type        = string
  default     = "patheya_admin"
}

variable "vpc_id" {
  type = string
}

variable "private_data_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  description = "From the calling environment's networking layer — ingress already scoped to the ECS task security group only."
  type        = string
}

variable "kms_key_arn" {
  description = "Encrypts RDS storage and the DATABASE_URL secret this module creates (one CMK per data class, matching modules/aurora's and modules/secrets-manager's existing convention)."
  type        = string
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "preferred_backup_window" {
  type    = string
  default = "17:00-18:00" # 22:30-23:30 IST, matching modules/aurora's own choice for consistency
}

variable "preferred_maintenance_window" {
  type    = string
  default = "sun:18:00-sun:19:00" # 23:30-00:30 IST Sunday, matching modules/aurora's own choice
}

variable "deletion_protection" {
  description = "false is appropriate ONLY for a temporary, intentionally-destroyable environment. Anything longer-lived than DEV+QA must set this true."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  type    = bool
  default = true
}

variable "performance_insights_enabled" {
  description = "Off by default — unnecessary cost/complexity for temporary DEV+QA scale (Phase 1 §6). Set true only if a concrete diagnostic need arises."
  type        = bool
  default     = false
}

variable "monitoring_interval_seconds" {
  description = "Enhanced Monitoring granularity. 0 disables it — the default here, for the same reason as performance_insights_enabled."
  type        = number
  default     = 0
}

variable "environment" {
  description = "Used only in the DATABASE_URL secret's naming path (patheya-express/<environment>/database-url), matching modules/secrets-manager's existing naming convention — not used for conditional logic."
  type        = string
}
