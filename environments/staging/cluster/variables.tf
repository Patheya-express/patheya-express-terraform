variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "endpoint_public_access_cidrs" {
  type = list(string)
}
