# modules/elasticache

ElastiCache Redis, cluster mode enabled, one replication group per environment.

## Cluster mode, at every shard count

`cluster-enabled = yes` is set unconditionally (`main.tf`'s parameter group) — including
development's 1-shard/0-replica shape. This matches
`cloud-architecture-blueprint.md` Section 6, which states "cluster mode enabled" as the
architecture decision itself, with shard/replica counts as the only thing that varies by
environment.

## Encryption in transit is a documented, deferred application-code dependency

`transit_encryption_enabled = true` and `auth_token` are both set — mandatory per
`platform-standards.md` Section 13 ("TLS 1.2+ in transit everywhere, no exceptions"). The
backend's current `RedisService` (`ioredis` client, `host`/`port` only) and `QueuesModule`
(`BullModule.forRoot`, same shape) have **no** `tls`/`password` options today. Turning this on at
the infrastructure layer without an application-code change **will break connectivity** on
`terraform apply`. This is a known, explicitly documented gap (not silently resolved by either
disabling TLS to avoid an app change, or making an app change this phase is out of scope for) —
see the Phase 4 final report's "documented conflicts" section and `docs/redis-guide.md`'s
"required application follow-up" for the exact two-line change needed.

## Endpoints

`num_shards = 1` (development/staging today) publishes no `configuration_endpoint` — use
`primary_endpoint`/`reader_endpoint` instead. `num_shards > 1` (production) publishes
`configuration_endpoint`, which a cluster-aware client resolves shards from automatically.
`docs/redis-guide.md` has the exact `ioredis` connection shape for each case.

## Inputs / Outputs

See `variables.tf` / `outputs.tf`.
