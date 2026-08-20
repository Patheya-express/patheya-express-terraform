variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_data_subnet_ids" {
  type = list(string)
}

variable "redis_security_group_id" {
  description = "From module.networking (Phase 2) — already scoped to 6379 from eks-node-sg only."
  type        = string
}

variable "kms_key_arn" {
  description = "Encrypts data at rest — this environment's \"redis\" KMS key."
  type        = string
}

variable "auth_token" {
  description = "From module.secrets-manager's random_password — never a literal value in any environment's tfvars."
  type        = string
  sensitive   = true
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  description = "cache.r6g.large in production per cloud-architecture-blueprint.md Section 6's table; a smaller class is appropriate for development/staging."
  type        = string
  default     = "cache.r6g.large"
}

variable "num_shards" {
  description = "3 in production, 1 in staging/development — cloud-architecture-blueprint.md Section 6's topology table."
  type        = number
  default     = 1
}

variable "replicas_per_shard" {
  description = "1 in production/staging (multi-AZ automatic failover), 0 in development (blueprint: \"single node, no replica — dev doesn't need failover, just needs to exist\")."
  type        = number
  default     = 0

  validation {
    condition     = var.replicas_per_shard >= 0 && var.replicas_per_shard <= 2
    error_message = "replicas_per_shard must be between 0 and 2."
  }
}

variable "snapshot_retention_days" {
  type    = number
  default = 7
}

variable "snapshot_window" {
  type    = string
  default = "18:00-19:00" # 23:30-00:30 IST
}

variable "maintenance_window" {
  type    = string
  default = "sun:19:30-sun:20:30" # 01:00-02:00 IST Sunday, after the snapshot window
}

variable "apply_immediately" {
  type    = bool
  default = false
}

variable "alarm_sns_topic_arn" {
  type = string
}
