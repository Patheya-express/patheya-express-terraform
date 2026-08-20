# Database operations guide

Day-to-day operational reference — what each alarm means and what to check first.

## Aurora alarms

| Alarm | Threshold | First thing to check |
| --- | --- | --- |
| `<prefix>-aurora-cpu-high` | CPU > 80%, 3 min | Performance Insights (top SQL by load) — a missing index or a new N+1 query pattern is the usual cause, not organic traffic growth |
| `<prefix>-aurora-freeable-memory-low` | < 256MiB, 3 min | Query plans doing large sorts/hash joins in memory; consider `work_mem` if isolated to a few queries, instance class step-up if broad |
| `<prefix>-aurora-connections-high` | > 400 (serverless) / 1000 (provisioned), 3 min | **PgBouncer pool sizing first** (`docs/pgbouncer-guide.md`'s `default_pool_size`/`max_client_conn`) — this almost never means Aurora itself needs to scale; a breach here with PgBouncer healthy means something is bypassing PgBouncer and connecting to Aurora directly, which should not be possible per `platform-standards.md` Section 16 |
| `<prefix>-aurora-replica-lag-high` | > 1000ms, 3 min | A single long-running write transaction, or a genuine write-throughput spike outpacing storage-layer replication — check Performance Insights on the writer |

## Redis alarms

| Alarm | Threshold | First thing to check |
| --- | --- | --- |
| `<prefix>-redis-cpu-high` | > 80%, 3 min | Expensive commands (`KEYS`, large `SMEMBERS`/`ZRANGE`) — Redis is single-threaded per shard; a single slow command blocks everything on that shard |
| `<prefix>-redis-memory-high` | > 80%, 3 min | Check eviction alarm too — memory pressure without evictions means TTLs are set correctly but the working set genuinely grew; consider a larger node type or more shards |
| `<prefix>-redis-connections-high` | > 8000, 3 min | Runaway connection creation (a reconnect loop somewhere) rather than legitimate load — BullMQ/ioredis pool connections once per process, not per operation |
| `<prefix>-redis-evictions-high` | > 0 in 3 min | Real data loss risk — BullMQ job data or presence cache is being evicted, not just naturally expiring via TTL. Treat as urgent, not informational |
| `<prefix>-redis-replication-lag-high` | > 5s, 3 min | Usually a large write burst; sustained lag suggests the replica's node type is undersized relative to the primary's write rate |

## Routine tasks

- **Connection audit**: `SHOW POOLS;` against PgBouncer's admin console (`psql -h pgbouncer
  -p 6432 -U pgbouncer_admin pgbouncer`) — confirms pool utilization matches expectations before
  assuming Aurora needs to scale.
- **Slow query review**: `postgresql` CloudWatch Logs export, filtered for
  `duration: > 1000 ms` (the `log_min_duration_statement` threshold set in
  `modules/aurora/main.tf`).
- **Secret rotation verification**: Aurora's master secret rotates automatically every 30 days —
  confirm via `aws secretsmanager describe-secret --secret-id <arn>`'s `LastRotatedDate`, not by
  assuming it happened silently.

## What's explicitly not covered yet

Dashboards (Grafana, Phase 5), query-level distributed tracing (OpenTelemetry/Jaeger, Phase 5),
and BullMQ queue-depth metrics (`patheya_bullmq_queue_depth`, requires the Prometheus exporter
`cloud-architecture-blueprint.md` Section 10 names — not installed in this phase). Until then,
this guide plus CloudWatch's own console are the operational surface.
