# modules/aurora

Aurora PostgreSQL cluster — writer + N readers, encrypted, RDS-managed credentials,
CloudWatch alarms, and an AWS Backup plan with cross-region copy.

## What this module does not do

- **Does not create a database user or run migrations.** `var.database_name` creates an empty
  database inside the cluster at creation time; Prisma's own migration history
  (`prisma/migrations/`) is what actually shapes the schema, run manually or via a future CI
  step — never by Terraform.
- **Does not create the master credential value.** `manage_master_user_password = true` — RDS
  generates, stores (in Secrets Manager, KMS-encrypted with `var.kms_key_arn`), and rotates it.
  This module never sees or handles the plaintext password.
- **Does not provision the DR account's backup vault.** `var.dr_backup_vault_arn` is a required
  input — the caller (`environments/<env>/data`) creates the DR-region vault via a second AWS
  provider alias (`aws.dr`) and passes its ARN in. See `docs/backup-guide.md` for why this is
  cross-**region**, not yet cross-**account** (the `patheya-dr` account from the blueprint's
  Section 2 account table doesn't exist yet).

## Serverless vs. provisioned

`var.serverless = true` (development/staging) uses Aurora Serverless v2 — `engine_mode =
"provisioned"` with a `serverlessv2_scaling_configuration` block is the correct, current
Terraform shape for this (the older `engine_mode = "serverless"` is Aurora Serverless **v1**,
deprecated, not used here). `var.serverless = false` (production) uses fixed `db.r6g.*` instance
classes per `cloud-architecture-blueprint.md` Section 5's table.

## Connecting

Nothing connects to this cluster's endpoints directly except PgBouncer
(`modules/eks-addons/pgbouncer.tf`) — see `docs/connection-guide.md`. Application code never
holds `writer_endpoint`/`reader_endpoint` in its own configuration.

## Inputs / Outputs

See `variables.tf` / `outputs.tf`.
