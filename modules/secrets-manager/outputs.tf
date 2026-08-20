output "redis_auth_token_secret_arn" {
  value = aws_secretsmanager_secret.redis_auth_token.arn
}

output "redis_auth_token" {
  value     = random_password.redis_auth_token.result
  sensitive = true
}

output "external_credential_secret_arns" {
  value = { for k, v in aws_secretsmanager_secret.external_credentials : k => v.arn }
}

output "secrets_path_prefix" {
  description = "patheya-express/<environment> — the IAM policy scope External Secrets Operator's IRSA role is granted (modules/eks-addons/external-secrets.tf)."
  value       = "patheya-express/${var.environment}"
}
