# Prometheus guide

`kube-prometheus-stack` (`prometheus-stack.tf`) — Prometheus, the Prometheus Operator (which
provides the `ServiceMonitor`/`PodMonitor`/`PrometheusRule`/`Probe` CRDs and admission webhooks),
node-exporter, and kube-state-metrics all come from this one Helm release. Alertmanager and
Grafana are separate sections of this guide (`alerting-guide.md`, `grafana-guide.md`) even though
they're the same Helm release, since operationally they're different concerns.

## Discovery scope

`serviceMonitorSelectorNilUsesHelmValues: false` (and the `podMonitor`/`rule`/`probe` equivalents)
— Prometheus discovers **every** `ServiceMonitor`/`PodMonitor`/`PrometheusRule` in the cluster,
not just ones carrying this specific Helm release's own label. Without this, every
`ServiceMonitor` `servicemonitors.tf` creates would be silently ignored — the chart's default
behavior only watches objects matching its own release, which is the single most common
kube-prometheus-stack misconfiguration this repository specifically avoids.

## Retention and storage

| Environment | Retention | PVC size | Replicas |
| --- | --- | --- | --- |
| Development | 7d | 20Gi | 1 |
| Staging | 15d | 50Gi | 1 |
| Production | 15d | 100Gi | 2 |

Uses the same `gp3` `StorageClass` every other stateful in-cluster workload uses
(`modules/eks-addons/storage.tf`, Phase 3) — no new StorageClass.

## What 2 replicas in production actually buys

HA against a single pod/node eviction — **not** query deduplication or long-term federation.
Prometheus's own 2-replica pattern means both replicas scrape independently and can each go
briefly missing without losing all metrics, but Grafana's Prometheus datasource points at one
Service that round-robins between them; a query issued at the exact moment one replica is
restarting can see a brief gap. This is an accepted, documented limitation — closing it requires
Thanos or Mimir (a query-federation layer), which is out of this phase's scope. Revisit only if
metrics-query availability actually becomes an incident driver at a growth tier where that
tradeoff starts to matter.

## Recording rules and alerts

Two categories in `prometheus-rules.tf`:
- **RED** (api-gateway request rate/errors/duration) — real PromQL, zero data until the
  application exists and emits `patheya_http_requests_total`/
  `patheya_http_request_duration_seconds_bucket` (platform-standards.md Section 12's naming
  convention).
- **USE** (node/pod/PVC utilization/saturation) — real data immediately, since node-exporter and
  kube-state-metrics already have something to scrape the moment this phase applies.

See `docs/sre-operations-guide.md` for what each alert actually means when it fires.

## Node placement

Pinned to the `system` node group (`nodeSelector`/`toleration` matching every other
platform-critical add-on) — Prometheus itself must never be scheduled onto a Karpenter-managed,
potentially spot-interruptible node, for the same reason NGINX/Karpenter/cert-manager aren't
either (Phase 3's established pattern).
