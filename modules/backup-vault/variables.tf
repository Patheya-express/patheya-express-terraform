variable "tags" {
  type = map(string)
}

variable "name" {
  description = "Full vault name, e.g. patheya-development-aurora-vault-dr."
  type        = string
}

variable "kms_key_arn" {
  description = "A KMS key in the SAME region this module's aws provider is configured for — KMS keys are region-scoped, so this cannot be the primary region's key when this module is called with a DR-region provider alias."
  type        = string
}
