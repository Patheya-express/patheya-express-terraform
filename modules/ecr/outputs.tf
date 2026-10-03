output "repository_urls" {
  description = "Keyed by app name — the image repository URL (ECS task definitions; historically Kustomize images.newName)."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  value = { for k, v in aws_ecr_repository.this : k => v.arn }
}
