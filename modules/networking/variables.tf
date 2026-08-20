variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "private_data_subnet_ids" {
  type = list(string)
}

variable "flow_log_kms_key_arn" {
  description = "From module.kms — encrypts the VPC Flow Logs CloudWatch Logs group."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention for VPC Flow Logs. 30 days in every environment, per platform-standards.md Section 11's \"30 days hot\" logging standard applied to network flow data too."
  type        = number
  default     = 30
}
