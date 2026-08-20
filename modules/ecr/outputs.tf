output "repository_urls" {
  description = "Keyed by app name — the value Kustomize's `images.newName` (backend/frontend k8s/ overlays) points at."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  value = { for k, v in aws_ecr_repository.this : k => v.arn }
}
