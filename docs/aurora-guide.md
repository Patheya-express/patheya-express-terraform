# Aurora guide

`modules/aurora`, called from each environment's `data/` stage (`environments/<env>/data/main.tf`).

## Topology per environment

| Environment | Mode | Writer | Readers | Backup retention | Deletion protection |
| --- | --- | --- | --- | --- | --- |
| Development | Serverless v2 (0.5–4 ACU) | `db.serverless` | 0 | 7 days | off |
| Staging | Serverless v2 (0.5–4 ACU) | `db.serverless` | 1 | 14 days | on |
| Production | Provisioned | `db.r6g.xlarge` | 2 × `db.r6g.large` | 35 days (Aurora's maximum) | on |

Matches `cloud-architecture-blueprint.md` Section 5 exactly — production's reader count and
instance classes are the blueprint's literal table values, not independently chosen.

## Credentials

The master user credential is **never** a Terraform-managed secret value. `manage_master_user_password
= true` on the `aws_rds_cluster` resource makes RDS itself generate, store (in Secrets Manager,
KMS-encrypted), and rotate it — a 30-day automatic rotation schedule is attached via
`aws_secretsmanager_secret_rotation`, using AWS's own RDS-managed rotation mechanism, not a
Lambda this repository authors or deploys.

Nothing except PgBouncer (`docs/pgbouncer-guide.md`) ever reads this secret directly — External
Secrets Operator syncs it into PgBouncer's `userlist.txt` and (separately) into a
`DATABASE_URL`-shaped Secret for the application, once deployed.

## TLS

`rds.force_ssl = 1` is set at the cluster parameter group level — a non-TLS connection attempt
is rejected by Aurora itself, not merely discouraged. Prisma's own `DATABASE_URL` independently
carries `sslmode=require` (`docs/connection-guide.md`) — client-side and server-side enforcement
both exist, neither depends on the other being correctly configured.

## Slow query logging

`log_min_duration_statement = 1000` (milliseconds) in the cluster parameter group — any query
slower than 1 second is logged to the `postgresql` CloudWatch Logs export
(`enabled_cloudwatch_logs_exports`). This is this phase's entire "slow query logging" deliverable
(this task's Section 9) — no separate log-shipping pipeline exists yet (Phase 5's Loki install is
what eventually aggregates it further).

## Performance Insights

On by default, 7-day (free tier) retention in development/staging, 731-day (2-year, paid tier) in
production — production's retention is sized for genuine incident postmortem lookback, not the
default free-tier window.

## Reconciling with a pre-existing database

If a `development`/`staging` Postgres database already exists outside this Terraform (e.g. from
local development against a different Postgres instance), `var.database_name` here creates a
**new**, empty database inside the new Aurora cluster — it does not migrate data from anywhere.
Schema and data population is a Prisma-migration-and-seed operation
(`apps/api-gateway/prisma/`), run manually once the cluster exists, never something this module
does.

## Alarms

`modules/aurora/monitoring.tf` — CPU, freeable memory, connection count, and (when
`reader_count > 0`) replica lag, all pointed at `module.alerting`'s SNS topic. See
`docs/database-operations-guide.md` for what each alarm actually means operationally.
