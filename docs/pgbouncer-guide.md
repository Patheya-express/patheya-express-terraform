# PgBouncer guide

`modules/eks-addons/pgbouncer.tf` — a `Deployment` in the `data-platform` namespace, not a Helm
chart (no maintained, canonical PgBouncer chart exists the way it does for Karpenter/NGINX/
cert-manager; this follows the same hand-written-manifest-via-Terraform pattern the backend
repo's own `k8s/base/` already uses).

## Why it exists

`cloud-architecture-blueprint.md` Section 5: Prisma's own connection pool is per-pod-instance:
at `api-gateway`'s HPA ceiling plus `workers`, naive per-pod Postgres connections would approach
Aurora's `max_connections` ceiling well before compute is actually the bottleneck. PgBouncer
pools transactions (`pool_mode = transaction`), not sessions, so a much smaller number of real
Aurora connections serves a much larger number of application-level logical connections.

## Two virtual databases, one process

`pgbouncer.ini`'s `[databases]` section defines `patheya_write` (→ Aurora's writer endpoint) and
`patheya_read` (→ Aurora's reader endpoint, or the writer endpoint when an environment has no
readers — development). The application selects which pool it wants by the database name in its
own connection string — `.../patheya_write` for every read-write Prisma operation,
`.../patheya_read` only for a future read-replica-aware query path (not built yet; today's
`DATABASE_URL` — see `docs/connection-guide.md` — points at `patheya_write` for everything, which
is correct and safe, just not yet exploiting read scaling).

## Credential flow (no plaintext password touches Terraform)

1. Aurora's RDS-managed master secret exists in Secrets Manager (`docs/aurora-guide.md`).
2. `external-secrets.tf`'s `pgbouncer_credentials_external_secret` (an `ExternalSecret`) syncs it
   into a Kubernetes `Secret` named `pgbouncer-credentials` in the `data-platform` namespace.
3. An **init container** (`render-userlist`, `busybox:1.36`) reads that Secret's `username`/
   `password` keys as env vars and writes `/etc/pgbouncer-generated/userlist.txt` — a
   `readOnlyRootFilesystem`-compatible `emptyDir` shared with the main container.
4. The main `pgbouncer` container starts with `auth_file` pointed at that generated file.

PgBouncer accepts a plaintext password in `userlist.txt` regardless of `auth_type` (it hashes/
verifies internally per the negotiated protocol) — this is documented PgBouncer behavior, not a
downgrade of `auth_type = scram-sha-256`, which still governs the actual wire-protocol
negotiation with connecting clients.

## Metrics

A `pgbouncer-exporter` sidecar (`prometheuscommunity/pgbouncer-exporter`) exposes `:9127/metrics`
on the same pod. No `ServiceMonitor` exists yet — Phase 5 installs Prometheus and the scrape
config; this phase's job is only to make sure the endpoint exists and is reachable once something
scrapes it.

## High availability

`platform-critical` priority class (pinned to the `system` node group, never spot-interruptible —
the same class Phase 3's NGINX Ingress and other platform-critical add-ons use), pod
anti-affinity, zone-aware `topologySpreadConstraints`, and a `PodDisruptionBudget`. Replica counts
and `minAvailable`: 1/0 in development, 2/1 in staging, 3/2 in production
(`environments/<env>/platform/main.tf`'s `pgbouncer_replica_count`/`pgbouncer_pdb_min_available`).

## Read-only root filesystem

`unix_socket_dir =` (empty, TCP-only) in `pgbouncer.ini` — PgBouncer needs to write nothing at
runtime except the generated `userlist.txt` (already on its own volume) and scratch space in
`/tmp` (a dedicated `emptyDir`), so `readOnlyRootFilesystem: true` holds for every container in
the pod, matching `platform-standards.md` Section 7's Kyverno-enforced baseline.
