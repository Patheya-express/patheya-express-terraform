# Data platform architecture

## Component diagram

```mermaid
flowchart TB
    subgraph EKS["EKS Cluster"]
        subgraph DataPlatformNS["data-platform namespace"]
            PGB[PgBouncer Deployment<br/>patheya_write / patheya_read]
        end
        subgraph BackendNS["patheya-backend namespace (prepared, not yet deployed)"]
            DBSecret[Secret: backend-database-url]
            RedisSecret[Secret: backend-redis-credentials]
        end
        subgraph ExtSecretsNS["external-secrets namespace"]
            ESO[External Secrets Operator]
            CSS[ClusterSecretStore: aws-secrets-manager]
        end
    end

    subgraph AWS["AWS — this environment's account/region"]
        AURORA[(Aurora PostgreSQL<br/>writer + readers)]
        REDIS[(ElastiCache Redis<br/>cluster mode enabled)]
        SM[Secrets Manager]
        BACKUP[AWS Backup vault<br/>primary region]
    end

    subgraph DR["ap-southeast-1"]
        BACKUPDR[AWS Backup vault<br/>DR region]
    end

    PGB -->|"5432, TLS"| AURORA
    ESO -->|IRSA| SM
    CSS --> ESO
    ESO -->|sync| DBSecret
    ESO -->|sync| RedisSecret
    ESO -->|sync| PGBCred[Secret: pgbouncer-credentials]
    PGBCred --> PGB
    AURORA -.nightly copy.-> BACKUP
    BACKUP -.cross-region copy.-> BACKUPDR
    RedisSecret -.future app read.-> REDIS
```

## Request path (once the application is deployed — Phase 4's blueprint-assigned app-code work)

```mermaid
sequenceDiagram
    participant App as api-gateway (Prisma)
    participant PGB as PgBouncer
    participant DB as Aurora writer
    participant Redis as ElastiCache

    App->>PGB: connect (DATABASE_URL, patheya_write)
    PGB->>DB: pooled connection (transaction mode)
    DB-->>PGB: result
    PGB-->>App: result
    App->>Redis: BullMQ enqueue / cache-aside read (TLS + AUTH, once app-code follow-up lands)
```

## Two-stage state, mirroring Phase 3's cluster/platform split

```mermaid
flowchart LR
    Network["environments/&lt;env&gt;<br/>(Phase 2 flat state)<br/>VPC, subnets, aurora-sg, redis-sg"]
    Data["environments/&lt;env&gt;/data<br/>Aurora, ElastiCache,<br/>Secrets Manager, alerting"]
    Cluster["environments/&lt;env&gt;/cluster<br/>(Phase 3)<br/>EKS control plane, OIDC"]
    Platform["environments/&lt;env&gt;/platform<br/>eks-addons: ... + ESO + PgBouncer"]

    Network --> Data
    Network --> Cluster
    Data --> Platform
    Cluster --> Platform
```

`data/` depends only on the flat network state (same dependency shape as `cluster/`) — it can
apply in parallel with `cluster/`, not after it. `platform/` is the one stage that depends on
**both**: it needs `cluster/`'s OIDC provider (for every IRSA role) and `data/`'s Aurora/Redis/
Secrets Manager outputs (for PgBouncer's config and every `ExternalSecret`'s `remoteRef`).

## Why a third state and not a fourth

An earlier design considered a separate `data-addons/` state (mirroring `cluster/` →
`platform/`) purely for PgBouncer/External Secrets Operator, to keep "AWS resources" and
"Kubernetes resources" cleanly separated per state. Rejected: `platform/` already exists
specifically as "the Kubernetes/Helm stage that needs `cluster/`'s outputs" — PgBouncer and
External Secrets Operator are exactly that, or Karpenter/NGINX/cert-manager wouldn't be either.
Adding a fourth state would replicate `platform/`'s provider configuration for no separation
benefit; extending the existing `platform/` module call is the smaller, more consistent change.
