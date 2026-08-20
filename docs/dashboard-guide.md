# Dashboard guide

11 dashboards (`grafana-dashboards.tf`), 3 folders. Section 8's broader "create dashboards for
Karpenter/AWS Load Balancer Controller/NGINX/External Secrets/Deployments/Namespaces/Load
Balancers" list is folded into these 11 as panels, not built as separate dashboards — see
"Consolidation" below for why.

## Folder: Infrastructure

| Dashboard | Covers |
| --- | --- |
| Cluster Overview | Node count, cluster CPU/memory, pods by namespace, Karpenter on-demand vs spot split, pending pods |
| Kubernetes Health | Deployment replica mismatch, CrashLoopBackOff, container restarts, PDB disruption budget, HPA status, ResourceQuota usage |
| Node Health | Per-node CPU/memory, disk pressure, filesystem usage, network throughput |
| Ingress | NGINX request rate/latency/5xx, AWS Load Balancer Controller reconcile errors, ExternalDNS sync errors |
| Networking | Node network errors, CoreDNS query rate/latency |
| Storage | PVC utilization, EBS CSI volume errors, bound/unbound PVC counts |
| Certificates | Days-until-expiry, certificate ready status, ACME order failures |

## Folder: Data Platform

| Dashboard | Covers |
| --- | --- |
| Aurora | CPU, freeable memory, connections, replica lag, read IOPS — all via the CloudWatch datasource, reusing Phase 4's already-existing metrics rather than re-deriving them in Prometheus |
| Redis | Engine CPU, memory usage, connections, evictions, replication lag — same CloudWatch-datasource pattern |
| PgBouncer | Active client/server connections, waiting clients, per-pool connections, average query duration — via Prometheus, scraping the exporter sidecar Phase 4 already deployed |

## Folder: Applications

| Dashboard | Covers |
| --- | --- |
| Application Overview | Request rate/error rate/p95 latency/BullMQ queue depth for `api-gateway` — **deliberately empty** (this task's Section 13 explicit instruction) until a future phase deploys the application |

## Consolidation decision

Section 8 additionally asks for dashboards covering "Deployments, Namespaces, Load Balancers,
Karpenter, AWS Load Balancer Controller, NGINX, External Secrets" as if each were its own
dashboard. This guide folds them into the 11 above by subject-matter fit (Deployments/Namespaces
→ Kubernetes Health; Load Balancers/NGINX → Ingress; Karpenter → Cluster Overview) rather than
creating 7 more thin, single-metric dashboards — Section 13's own list of 11 named dashboards is
treated as the authoritative "what to build," Section 8's list as "what those 11 need to cover."

## Adding a new dashboard

Add an entry to `modules/observability/grafana-dashboards.tf`'s `local.dashboards` map — every
panel object shares one uniform schema (`title`/`type`/`datasource`/`query`/`unit`/`cw_namespace`/
`cw_metric`/`cw_stat`, with `null` for whichever half doesn't apply to a given panel's
datasource). This uniform shape isn't a style preference — HCL requires every value in a map/list
literal to type-unify, so a Prometheus-only panel schema and a CloudWatch-only one can't coexist
in the same `local.dashboards` map without it.

## Panel query correctness

Kubernetes/node-level panels query real, already-flowing metric names (kube-state-metrics/
node-exporter's own standard metric names) — these render real data the moment
`terraform apply` completes. Aurora/Redis panels query real CloudWatch metrics Phase 4's alarms
already prove exist. PgBouncer panels query the exporter's real metric names. Only the
Application Overview dashboard's `patheya_*` queries have no data yet, by explicit design.
