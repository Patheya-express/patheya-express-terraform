# Backup guide

Two independent backup mechanisms for Aurora, deliberately not relying on each other — per
`cloud-architecture-blueprint.md` Section 12: "a second, independent recovery path that doesn't
depend on [the first] staying healthy."

## 1. Aurora's own automated backups

`backup_retention_days` (`modules/aurora`) — continuous backup enabling point-in-time recovery
(PITR) to any second within the retention window. 7 days (development), 14 days (staging), 35
days — Aurora's maximum — (production). Runs inside the `preferred_backup_window`
(`17:00–18:00 UTC` / `22:30–23:30 IST`, before AWS Backup's own nightly job below).

## 2. AWS Backup — nightly snapshot + cross-region copy

`modules/aurora/backup.tf` — an `aws_backup_plan` with one nightly rule (`19:00 UTC` /
`00:30 IST`), targeting a primary-region vault (`modules/aurora`'s own
`aws_backup_vault.primary`) and copying to a DR-region vault
(`modules/backup-vault`, called from `environments/<env>/data/main.tf` with a `provider =
aws.dr` override).

### Cross-region today, not yet cross-account

The blueprint's Section 12 describes "nightly snapshot copy to the DR account." The `patheya-dr`
AWS account (blueprint Section 2's account table) does not exist yet — only `management`,
`security`, `shared-services`, `development`, `staging`, `production` were provisioned in Phase
2. This phase implements the cross-**region** copy (`ap-south-1` → `ap-southeast-1`, same
account) as the closest correct implementation available today, and documents the cross-
**account** step as deferred until the `patheya-dr` account is provisioned in a future phase —
see the Phase 4 final report's documented-conflicts section. The mechanism (an `aws_backup_plan`
`copy_action`) doesn't change when that account exists; only the destination vault's account
changes, via a cross-account vault access policy grant that phase would add.

## Restore procedure

1. **Aurora PITR** (mechanism 1, most common case — accidental data change, not full data loss):
   `aws rds restore-db-cluster-to-point-in-time` targeting a specific timestamp within the
   retention window, into a **new** cluster identifier (Aurora never restores in place) — then
   cut the application over via a Terraform variable change to the new cluster's endpoint, or
   promote the restored cluster and rename.
2. **AWS Backup restore** (mechanism 2 — corrupted/deleted primary-region backups, or a genuine
   DR scenario): restore from the DR-region vault via `aws backup start-restore-job`, producing a
   new Aurora cluster in `ap-southeast-1`. This is the same recovery path a real regional failure
   in `ap-south-1` would use.

Both procedures always create a **new** cluster — this repository's Terraform state for the
original cluster is untouched by a restore, and the state for the restored cluster must be
imported or the environment's `data/` stage's `aws_rds_cluster` resource address must be pointed
at the new identifier before the next `terraform apply`, to avoid Terraform trying to recreate
the original.

## Backup validation

No automated restore-and-verify job exists yet (that's meaningfully more infrastructure — a
scheduled Lambda or CI job that restores into a scratch cluster, runs a smoke query, and tears it
down — reserved for when Phase 5's CI/observability foundation exists to run and alert on it).
Until then: `docs/eks-disaster-recovery.md`'s quarterly-drill cadence (inherited from Phase 3,
scoped there to cluster rebuild) is the right home for a manual "restore the staging backup and
confirm the schema/row counts look right" check — add it to that same quarterly exercise rather
than inventing a separate, easily-forgotten schedule (`platform-standards.md` Section 19).
