variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "ecr_registry_host" {
  description = "From environments/shared-services's ecr_repository_urls output — cross-account, supplied as a tfvar, matching production's apex_zone_id pattern. See modules/supply-chain-security's variable of the same name."
  type        = string
}
