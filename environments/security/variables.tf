variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "organization_id" {
  description = "From environments/management's `organization_id` output — copy in after that environment's first apply."
  type        = string
}

variable "management_account_id" {
  type = string
}
