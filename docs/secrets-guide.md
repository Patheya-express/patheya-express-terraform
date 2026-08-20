# Secrets guide

Two categories, handled differently — see `modules/secrets-manager`'s README for the reasoning.

## Terraform-generated (populated automatically on `apply`)

| Secret | Source | Rotation |
| --- | --- | --- |
| Aurora master credential | `manage_master_user_password = true` on `aws_rds_cluster` (RDS-managed, not this module) | Automatic, 30 days, AWS's own RDS-managed rotation mechanism |
| `patheya-express/<env>/redis-auth-token` | `random_password` in `modules/secrets-manager` | Manual — rotating requires a coordinated app-side reconnect (same rationale as JWT secrets below) |

## Human-populated (empty containers only — Terraform never writes a value)

`patheya-express/<env>/jwt-signing-key`, `.../cloudinary`, `.../razorpay`, `.../smtp` —
`modules/secrets-manager` creates the `aws_secretsmanager_secret` container (name, KMS
encryption, tags) and nothing else. Populate each one **once**, post-apply, with the AWS CLI, using
**exactly** the JSON shape below — `modules/eks-addons/external-secrets.tf`'s
`backend_app_secrets_external_secret` (Phase 9) templates these specific field names into the
`backend-app-secrets` Kubernetes Secret every `api-gateway`/`workers` pod consumes; a different key
name in the JSON silently produces an empty environment variable, not an error ESO surfaces loudly.

```bash
aws secretsmanager put-secret-value \
  --secret-id patheya-express/production/jwt-signing-key \
  --secret-string '{"accessSecret":"...","refreshSecret":"..."}' \
  --region ap-south-1

aws secretsmanager put-secret-value \
  --secret-id patheya-express/production/cloudinary \
  --secret-string '{"cloudName":"...","apiKey":"...","apiSecret":"..."}' \
  --region ap-south-1

aws secretsmanager put-secret-value \
  --secret-id patheya-express/production/razorpay \
  --secret-string '{"keyId":"...","keySecret":"..."}' \
  --region ap-south-1

aws secretsmanager put-secret-value \
  --secret-id patheya-express/production/smtp \
  --secret-string '{"host":"...","port":"587","user":"...","pass":"...","from":"..."}' \
  --region ap-south-1
```

Use a JSON object (not a bare string) for any secret with more than one field — this is what lets
External Secrets Operator's `dataFrom.extract` sync every field into separate Kubernetes Secret
keys in one `ExternalSecret`, the same pattern already used for Aurora's master credential.

**Known gap**: `BANK_ACCOUNT_ENCRYPTION_KEY` (`env.validation.ts`, optional/enforced-at-point-of-use)
has no corresponding Secrets Manager entry yet — no `external_credential_secrets` container was
ever created for it. Add one (matching this same pattern) before any code path that decrypts a
restaurant bank account is exercised for real.

**Never** commit a real value to this repository, a `terraform.tfvars` file, or a CI log — this is
precisely the placeholder-secret risk `cloud-architecture-blueprint.md` Section 11 and
`platform-standards.md` Section 13 both flag Phase 1A's `secret.env.example` as needing to retire.

## Why JWT rotation is manual, specifically

`platform-standards.md` Section 13: "JWT signing secrets — manual rotation only (a JWT secret
rotation invalidates every active session, which is a deliberate, communicated action, never an
automated surprise)." Automatic rotation is deliberately **not** configured for this one secret,
unlike Redis's AUTH token or Aurora's master credential, both of which support a
reconnect-transparent rotation their respective clients (ElastiCache's `auth_token_update_strategy
= "ROTATE"`, RDS's managed secret) handle without an application-visible session invalidation.

## External Secrets Operator's access

`modules/eks-addons/external-secrets.tf`'s IRSA policy scopes `secretsmanager:GetSecretValue`/
`DescribeSecret` to `patheya-express/<environment>/*` plus the one Aurora master-secret ARN
explicitly (RDS-managed secrets don't follow this repository's naming convention — see that
file's comment). No wildcard across environments, no wildcard across the account.

## Naming

`patheya-express/<environment>/<purpose>` — see `modules/secrets-manager`'s README for why the
`<environment>` path segment is what makes IAM prefix-scoping possible at all.
