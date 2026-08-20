output "tags" {
  description = "The complete mandatory tag map (platform-standards.md Section 5), ready to merge into any resource's `tags` argument."
  value       = local.tags
}

output "name_prefix" {
  description = "patheya-<environment> — the base for every Section 4 resource-naming pattern."
  value       = local.name_prefix
}
