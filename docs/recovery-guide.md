# Recovery guide

Scope: losing or corrupting the **data layer** (Aurora, ElastiCache) — for losing the EKS cluster
itself, see `docs/eks-disaster-recovery.md` (Phase 3); the two are independent failure domains and
recover independently (Phase 3's cluster rebuild doesn't touch Aurora/Redis at all, since they
live in a separate Terraform state — `data/` — that the cluster's loss doesn't affect).

## Aurora recovery

See `docs/backup-guide.md`'s "Restore procedure" — PITR for point-in-time data issues, AWS Backup
DR-region restore for a full primary-region loss.

## Redis recovery

ElastiCache's own automated snapshots (`snapshot_retention_days` — 3/7/7 days for
development/staging/production) are the only backup mechanism for Redis — no AWS Backup
integration for ElastiCache exists the way it does for Aurora. Restore via
`aws elasticache create-replication-group --snapshot-name <name>`, producing a **new**
replication group (same "restore never happens in place" pattern as Aurora).

**What's actually lost if Redis disappears with zero restore**: per `docs/redis-guide.md`'s
keyspace table, everything Redis holds is either re-derivable (BullMQ jobs — the underlying
Aurora writes that created them are still there; a job re-enqueue sweep is a possible, if
imperfect, application-level mitigation) or genuinely ephemeral by design (cache-aside entries,
presence data, distributed locks) — this is precisely why `cloud-architecture-blueprint.md`'s
ADR-003 chose ElastiCache over the stronger-durability MemoryDB: "BullMQ jobs are re-creatable
from Aurora state if truly lost." A Redis restore-from-snapshot is a convenience that shortens
recovery time, not a data-loss-prevention requirement the way Aurora's backups are.

## Recovery objectives

RPO ≤ 5 minutes, RTO ≤ 60 minutes (`cloud-architecture-blueprint.md` Section 12) — the same
platform-wide targets Phase 3's cluster-DR guide uses. For Aurora specifically: PITR's continuous
backup gives an RPO close to zero for the common (non-regional-failure) case; the AWS Backup
nightly-copy path's RPO is bounded by "up to 24 hours" in the genuine regional-failure case, which
is why Aurora Global Database (near-real-time replication) is the named upgrade path once DR
moves from pilot-light to warm-standby (blueprint Section 12) — not yet implemented in this
phase, which only builds the nightly-snapshot-copy leg.

## Failover trigger

Manual, human-confirmed — same reasoning as Phase 3's cluster-DR guide: an automatic failover on
a false-positive health check is a worse incident than a slower, confirmed one
(`platform-standards.md` Section 19).

## Drills

Fold into the same quarterly exercise `docs/eks-disaster-recovery.md` and `docs/backup-guide.md`
both reference — a single quarterly DR drill covering cluster rebuild, Aurora restore, and Redis
restore together is more representative of a real incident than three separate, disconnected
drills.
