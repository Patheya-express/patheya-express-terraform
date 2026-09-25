output "security_group_id" {
  value = aws_security_group.this.id
}

output "tailscale_authkey_secret_arn" {
  description = "Populate this secret's value out-of-band before the instance can join the tailnet - see main.tf's comment on aws_secretsmanager_secret.tailscale_authkey."
  value       = aws_secretsmanager_secret.tailscale_authkey.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
