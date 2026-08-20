variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "endpoint_public_access_cidrs" {
  description = "See modules/eks's variable of the same name — no default, must be a real, known CIDR list (never 0.0.0.0/0)."
  type        = list(string)
}
