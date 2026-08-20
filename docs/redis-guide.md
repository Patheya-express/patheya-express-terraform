# Redis guide

`modules/elasticache`, called from each environment's `data/` stage.

## Topology per environment

| Environment | Shards | Replicas/shard | Node type | Failover |
| --- | --- | --- | --- | --- |
| Development | 1 | 0 | `cache.t4g.micro` | off — "single node, no replica ... just needs to exist" |
| Staging | 1 | 1 | `cache.t4g.small` | on |
| Production | 3 | 1 | `cache.r6g.large` | on, Multi-AZ |

Matches `cloud-architecture-blueprint.md` Section 6's table exactly. Cluster mode
(`cluster-enabled = yes`) is set unconditionally across every row — including development's
single-node shape — because the blueprint states cluster mode as the architecture decision
itself, not something that only applies above a certain shard count.

## What runs on it (infrastructure prepared, application code unchanged)

- **BullMQ** — all 6 existing queues (`notifications`, `dispatch`, `payments`, `search`,
  `tickets`, `orders`). No code change: `QueuesModule`'s `BullModule.forRoot` already reads
  `REDIS_HOST`/`REDIS_PORT` from environment/config — pointing those at this cluster's endpoint
  is a configuration change, not a code change. See the important TLS caveat below.
- **Socket.IO Redis adapter** — infrastructure only. The actual `@socket.io/redis-adapter`
  wiring in `realtime.gateway.ts` is application code, explicitly out of this phase's scope (see
  the Phase 4 final report's documented-conflicts section for why the blueprint's own Phase 4
  roadmap listed this as an app-code deliverable that this infrastructure-only phase does not
  implement).
- **Distributed locks / cache-aside / presence-tracking cache** — same story: the Redis endpoint
  exists, encrypted and authenticated; the Redlock-pattern lock code and cache-aside read paths
  are application code not touched here.

## Keyspace strategy (documented, not enforced by this phase's infrastructure)

| Prefix | Owner | TTL |
| --- | --- | --- |
| `bull:<queue>:*` | BullMQ (managed entirely by the `bullmq` library's own key scheme) | Per BullMQ's own job lifecycle — not a manual TTL |
| `user:<id>` / `order:<id>` / `restaurant:<id>` / `ticket:<id>` | Socket.IO room state (once the adapter lands) | Connection-lifetime, not a stored TTL |
| `cache:<resource>:<id>` | Cache-aside reads (restaurant/menu listings) | 60–300s per `cloud-architecture-blueprint.md` Section 6 |
| `lock:<resource>:<id>` | Distributed locks (Redlock pattern) | Single-digit seconds, matching the lock's own hold time |
| `presence:<partner-id>` | Delivery-partner presence/location | Short (tens of seconds) — a stale entry should expire, not persist |

This table documents the **intended** shape (matching the existing `RedisService.set(key, value,
ttl)` signature, which already supports per-key TTLs) — it is not itself enforced by any
Terraform resource; ElastiCache has no way to enforce an application's own key-naming discipline.

## TLS/AUTH — a documented application-code follow-up required

`transit_encryption_enabled = true` and `auth_token` (Secrets-Manager-stored, Terraform-generated)
are both set, per `platform-standards.md` Section 13 ("TLS 1.2+ in transit everywhere, no
exceptions"). The backend's current `RedisService` (`ioredis`, `host`/`port` only) and
`QueuesModule`'s `BullModule.forRoot` (identical shape) have **no** `tls`/`password` options
today. Connecting to this cluster as currently provisioned **will fail** until a small,
application-code change adds:

```ts
new Redis({
  host: process.env.REDIS_HOST,
  port: Number(process.env.REDIS_PORT),
  password: process.env.REDIS_AUTH_TOKEN,
  tls: {},
});
```

...to both `RedisService`'s constructor and `QueuesModule`'s `BullModule.forRoot` connection
block. This is a known, explicitly flagged gap — not silently resolved by disabling encryption to
avoid touching application code (which this phase's "no application changes" scope forbids either
way). See the Phase 4 final report's documented-conflicts section.

## Endpoints

`num_shards = 1` (development/staging) publishes no `configuration_endpoint` — use
`primary_endpoint`/`reader_endpoint`. `num_shards > 1` (production) publishes
`configuration_endpoint` — a cluster-aware client (`ioredis` with `cluster: true`, once the
application-code TLS/AUTH follow-up above lands) resolves shards from that single endpoint
automatically.

## Alarms

`modules/elasticache/monitoring.tf` — CPU, memory, connection count, evictions, and (when
replicas exist) replication lag, all pointed at `module.alerting`'s SNS topic.
