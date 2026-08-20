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
