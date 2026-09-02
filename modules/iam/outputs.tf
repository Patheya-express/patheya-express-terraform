output "terraform_role_arn" {
  description = "Configure as the `role-to-assume` input on this account's `aws-actions/configure-aws-credentials` GitHub Actions step."
  value       = aws_iam_role.terraform.arn
}

output "permission_boundary_arn" {
  value = local.permission_boundary_arn
}

output "github_oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "backend_ecr_push_role_arn" {
  description = "Configure as the `role-to-assume` input on patheya-express-platform's release workflow's `aws-actions/configure-aws-credentials` step. Null in any account that doesn't own the backend ECR repository (backend_ecr_repository_arns left at its empty default) — only environments/shared-services populates this today."
  value       = length(aws_iam_role.backend_ecr_push) > 0 ? aws_iam_role.backend_ecr_push[0].arn : null
}

output "frontend_ecr_push_role_arn" {
  description = "Configure as the `role-to-assume` input on the frontend repo's docker-publish workflow's `aws-actions/configure-aws-credentials` step. Null in any account that doesn't own the frontend ECR repositories — see backend_ecr_push_role_arn."
  value       = length(aws_iam_role.frontend_ecr_push) > 0 ? aws_iam_role.frontend_ecr_push[0].arn : null
}
