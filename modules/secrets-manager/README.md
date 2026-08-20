# modules/secrets-manager

Two categories of secret, handled differently on purpose:

1. **`redis-auth-token`** — Terraform-generated (`random_password`), because it's a credential
   this platform itself invents for ElastiCache's AUTH protocol, not an external system's
   credential. Written to Secrets Manager immediately (`aws_secretsmanager_secret_version`), so
   `terraform apply` alone is sufficient to make it usable.
2. **`var.external_credential_secrets`** (JWT signing key, Cloudinary, Razorpay, SMTP) — this
   module creates only the empty `aws_secretsmanager_secret` container. It never writes a
   version, because it has no legitimate value to write — these are real third-party credentials
   that must come from a human, out-of-band. See `docs/secrets-guide.md` for the exact AWS CLI
   command an operator runs once, post-apply, to populate each one.

## Naming

`patheya-express/<environment>/<purpose>` — e.g. `patheya-express/production/redis-auth-token`,
`patheya-express/production/razorpay`. The `<environment>` path segment is what lets External
Secrets Operator's IRSA policy (`modules/eks-addons/external-secrets.tf`) scope
`secretsmanager:GetSecretValue` to exactly this environment's secrets via a prefix match, never
every secret in the account.

## Aurora's own credential is not here

The Aurora cluster's master-user credential is **not** created by this module — `modules/aurora`
uses RDS's native `manage_master_user_password = true`, which creates and rotates its own
AWS-managed Secrets Manager secret with zero Terraform-side password handling at all. Duplicating
that as a second, Terraform-generated secret here would create two sources of truth for the same
credential. See `modules/aurora`'s README for the exact secret ARN output consumers should use.

## Inputs / Outputs

See `variables.tf` / `outputs.tf` — both documented inline per platform-standards.md Section 9's
"every variable has a description" requirement.
