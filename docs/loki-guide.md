# Loki guide

`loki.tf` — S3-backed (never PVC-only; log volume doesn't fit block storage economics the way
Prometheus's much smaller, short-retention TSDB does), TSDB index, structured-metadata-aware.

## Deployment mode

| Environment | Mode | Why |
| --- | --- | --- |
| Development / Staging | `SingleBinary` | One component does everything — simplest operational shape at low log volume |
| Production | `SimpleScalable` | Read/write/backend split so ingestion and query load scale independently |

Same environment-tiered-complexity pattern already used for Redis (single-node dev → cluster-mode
production) and Aurora (serverless → provisioned) — not a new pattern introduced for Loki.

## Retention

7 / 14 / 30 days hot (queryable) in development/staging/production respectively
(`loki.limits_config.retention_period`), matching `platform-standards.md` Section 11's "7 days
hot, no cold tier" for non-production. Production additionally gets a cold tier: `storage.tf`'s
S3 lifecycle rule transitions objects to Glacier Instant Retrieval after 30 days, expiring at 365
days — Section 11's "30 days hot + 1 year cold, production only."

## Index and compression

TSDB index (Loki's modern default, schema v13) — the boltdb-shipper index this repository does
**not** use is Loki's older, deprecated index format. Chunk compression uses Loki's own default
(snappy) — not overridden, no reason to.

## Structured metadata, not extra labels

`requestId`/`correlationId`/`traceId` (platform-standards.md Section 11's correlation IDs) are
extracted by Promtail's pipeline (`promtail_values.config.snippets.pipelineStages`) as
**structured metadata**, not Loki labels. This is the load-bearing distinction: a Loki label
becomes part of the index — one label per distinct `requestId` value would make the index grow
without bound (every request gets its own "series"). Structured metadata (Loki 3.x) rides with
the log line without touching the index at all, so cardinality stays bounded to the genuinely
low-cardinality label set (`namespace`, `pod`, `container`, `level`) while still making
`requestId`/`correlationId`/`traceId` queryable and filterable.

## Security

`auth_enabled: false` — no per-tenant multi-tenancy, since this is a single-tenant (per
environment/cluster) deployment; the Kubernetes `NetworkPolicy` default-deny plus the `logging`
namespace's own boundary is the access control, not a Loki-level tenant ID. IRSA
(`modules/observability/iam.tf`'s `loki` role) is scoped to exactly this environment's own S3
bucket + KMS key, nothing broader.

## Promtail

DaemonSet — one pod per node, tolerating every taint (including `system` node group's
`CriticalAddonsOnly`) so it collects logs from every pod on every node, not just untainted ones.
Parses Phase 1A's existing Winston JSON log shape directly; no application-code change needed —
the logs were already structured JSON on stdout (`LOG_TO_FILE=false` in production, an existing
Phase 1A decision this phase's log pipeline was built specifically to consume).
