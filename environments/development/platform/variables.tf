variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "ecr_registry_host" {
  description = "From environments/shared-services's ecr_repository_urls output (any one entry's host portion, e.g. <shared-services-account-id>.dkr.ecr.ap-south-1.amazonaws.com) — cross-account, supplied as a tfvar rather than a cross-account terraform_remote_state read, matching the exact pattern production's apex_zone_id/apex_certificate_arn already use. See modules/supply-chain-security's variable of the same name."
  type        = string
}
