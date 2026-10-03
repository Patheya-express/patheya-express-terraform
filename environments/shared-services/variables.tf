variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "organization_id" {
  description = "From environments/management's output — scopes the ECR cross-account pull policy to org members only."
  type        = string
}

variable "development_zone_name_servers" {
  description = "From environments/development's route53 module `name_servers` output, after that environment's first apply."
  type        = list(string)
}

variable "staging_zone_name_servers" {
  description = "From environments/staging's route53 module `name_servers` output, after that environment's first apply."
  type        = list(string)
}

variable "production_account_id" {
  description = "The Production workload account — the only account granted ECR pull, and the only account allowed to assume the Production DNS-records role (production-dns.tf)."
  type        = string
  default     = "512297269884"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.production_account_id))
    error_message = "production_account_id must be a 12-digit AWS account ID."
  }
}

variable "production_dns_hostnames" {
  description = "First-level labels under the apex that Production's app layer may manage records for (each also gets its ACM DNS-validation record, `_<token>.<label>.<apex>`). Nothing outside this list — including the apex itself — is writable by Production."
  type        = list(string)
  default     = ["api", "admin", "customer", "restaurant", "delivery"]
}
