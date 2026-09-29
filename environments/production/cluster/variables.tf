variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "endpoint_public_access_cidrs" {
  type = list(string)
}

variable "operating_mode" {
  description = "build | live — see docs/production-lifecycle.md. No idle value: in idle this layer is destroyed entirely. Deliberately no default; set in the committed operating-mode.auto.tfvars."
  type        = string

  validation {
    condition     = contains(["build", "live"], var.operating_mode)
    error_message = "operating_mode must be build or live for the cluster layer — idle means this layer is destroyed, not applied."
  }
}
