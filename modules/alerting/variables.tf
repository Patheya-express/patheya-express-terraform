variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  description = "Encrypts the SNS topic at rest — reuses the environment's own KMS key, no dedicated alerting key."
  type        = string
}

variable "topic_name" {
  description = "Suffix appended to name_prefix — e.g. \"alerts-database\" produces patheya-<env>-alerts-database (platform-standards.md Section 4's SNS naming pattern)."
  type        = string
}
