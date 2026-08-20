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
  description = "Configure as the `role-to-assume` input on patheya-express-platform's release workflow's `aws-actions/configure-aws-credentials` step."
  value       = aws_iam_role.backend_ecr_push.arn
}

output "frontend_ecr_push_role_arn" {
  description = "Configure as the `role-to-assume` input on the frontend repo's docker-publish workflow's `aws-actions/configure-aws-credentials` step."
  value       = aws_iam_role.frontend_ecr_push.arn
}
