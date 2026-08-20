variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "keys" {
  description = <<-EOT
    One customer-managed KMS key per data class — key alias becomes
    alias/<name_prefix>-<key>, matching platform-standards.md Section 4. Only instantiate the data
    classes a given environment actually has resources for right now (e.g. Phase 2 only needs
    "cloudtrail-logs" and "ecr" — "aurora"/"redis"/"ebs" get added in Phase 4/3 when those services
    exist, not created idle ahead of time).
  EOT
  type = map(object({
    description          = string
    additional_services  = optional(list(string), []) # e.g. ["logs.amazonaws.com"] — service principals allowed to use the key beyond the account root
    key_administrators   = optional(list(string), []) # additional IAM ARNs (beyond account root) allowed to manage (not just use) the key
    enable_rotation      = optional(bool, true)
    deletion_window_days = optional(number, 30)
  }))
}
