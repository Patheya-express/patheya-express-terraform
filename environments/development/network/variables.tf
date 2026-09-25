variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "nlb_allowed_cidrs" {
  description = "Cloudflare's current published IPv4 edge ranges (https://www.cloudflare.com/ips-v4/) — see modules/networking's own variable description for why this isn't hardcoded or defaulted. Required; populate via terraform.tfvars (gitignored) before applying this environment for real."
  type        = list(string)
}
