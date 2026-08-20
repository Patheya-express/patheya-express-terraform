# Connection guide

Who connects to what, and through which layer — the enforced answer, not just the intended one.

## Database

```
Prisma (api-gateway / workers) → PgBouncer (data-platform ns, ClusterIP :6432) → Aurora
```

No application code holds an Aurora endpoint. `DATABASE_URL` (synced by
`backend_database_url_external_secret`, `modules/eks-addons/external-secrets.tf`) is:

```
postgresql://<user>:<password>@pgbouncer.data-platform.svc.cluster.local:6432/patheya_write?sslmode=require
```

`platform-standards.md` Section 16: "no application code connects directly to the Aurora
writer/reader endpoints ... enforced by there being no other connection string anywhere in
configuration." The only place an Aurora endpoint appears in this repository is
`modules/eks-addons/pgbouncer.tf`'s ConfigMap.

## Cache / queue

```
ioredis (RedisService, BullMQ) → ElastiCache Redis directly (no pooler — Redis handles
connection volume natively; PgBouncer's role is Postgres-specific)
```

`REDIS_HOST`/`REDIS_PORT`/`REDIS_AUTH_TOKEN` are synced by `backend_redis_credentials_external_secret`
into the `backend-redis-credentials` Secret in `patheya-backend`. See `docs/redis-guide.md`'s TLS/
AUTH section for the required (not yet made) `ioredis` client change before this actually connects
successfully.

## Secrets

```
Secrets Manager → External Secrets Operator (IRSA) → Kubernetes Secret → Pod env/volume
```

Never Secrets Manager → application code directly (no AWS SDK call to Secrets Manager exists or
is planned in application code) — the Kubernetes Secret is always the interface the application
reads, matching `platform-standards.md` Section 13.

## Storage (reviewed, unchanged)

`apps/api-gateway/src/modules/storage/` — `StorageProvider` interface
(`upload`/`replace`/`delete`/`exists`/`getUrl`/`checkHealth`), with `CloudinaryStorageProvider`
as the only active implementation (`LocalStorageProvider` remains for single-replica local dev;
the S3 provider referenced in `cloud-architecture-blueprint.md` Section 7 was already removed
from this repository — nothing to reconcile). `STORAGE_DRIVER=cloudinary` is a `ConfigMap` value,
already how the backend repo's `k8s/base/configmap.yaml` selects it — this phase makes no code or
provider change, matching Section 7's "no S3 migration, Cloudinary remains primary" decision and
this phase's own "no application changes" scope. Cloudinary's own API credentials are one of the
external-credential secrets this phase provisions an empty container for
(`docs/secrets-guide.md`'s `patheya-express/<env>/cloudinary`) — the only storage-related change
this phase makes is giving that credential a real, rotatable home instead of a Kustomize
placeholder.

## What's still a placeholder

Everything above describes infrastructure that exists once this phase's Terraform is applied.
The **application** doesn't read any of it yet — no Deployment for `api-gateway`/`workers` exists
in this repository (that's Phase 4's blueprint-assigned application-code work, explicitly out of
this infrastructure-only phase's scope; see the Phase 4 final report). Once a future phase
deploys the application, its Deployment's `envFrom`/`env` should reference the
`backend-database-url` and `backend-redis-credentials` Secrets by name — both already exist,
namespace `patheya-backend`, ready to be mounted.
