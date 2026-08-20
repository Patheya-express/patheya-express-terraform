# Observability guide

The top-level map of Phase 5 — start here, then follow to the per-component guide for depth.

## What's installed, where

| Component | Namespace | Guide |
| --- | --- | --- |
| Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, Prometheus Operator | `monitoring` | `prometheus-guide.md`, `grafana-guide.md`, `alerting-guide.md` |
| Loki, Promtail | `logging` | `loki-guide.md` |
| Tempo | `tracing` | `tempo-guide.md` |
| OpenTelemetry Collector | `observability` (new) | `otel-guide.md` |

`monitoring`/`logging`/`tracing` already existed, empty, since Phase 3 — this phase is what
finally populates them. `observability` is the one genuinely new namespace.

## How this reuses Phase 3/4

- **Storage class**: Prometheus/Alertmanager/Grafana/Loki (SingleBinary mode) PVCs use the same
  `gp3` `StorageClass` Phase 3's `modules/eks-addons/storage.tf` already created — no new
  StorageClass.
- **ClusterSecretStore**: the Grafana admin credential and Alertmanager's two placeholder
  receiver secrets sync through the exact same `ClusterSecretStore` Phase 4's External Secrets
  Operator installed — no second ESO install, no second store.
- **Metrics endpoints**: NGINX Ingress, PgBouncer's exporter, Karpenter, the AWS Load Balancer
  Controller, ExternalDNS, cert-manager, and External Secrets Operator all already expose
  `/metrics` — several with a comment in their own Phase 3/4 `.tf` file saying "nothing scrapes
  it yet." `modules/observability/servicemonitors.tf` is what finally does, with zero changes to
  any Phase 3/4 chart's own values.
- **Aurora/Redis metrics**: not duplicated into Prometheus. Phase 4 already put real CloudWatch
  alarms on both; this phase adds a read-only CloudWatch Grafana datasource (IRSA-scoped) so the
  Aurora/Redis/PgBouncer dashboards can query that same data directly, instead of standing up a
  second `cloudwatch-exporter` deployment to re-derive metrics CloudWatch already has.

## Documented blueprint conflict: Tempo, not Jaeger

`cloud-architecture-blueprint.md` Section 10 names **Jaeger** as the tracing backend
("OpenTelemetry SDK (NestJS) → Jaeger"). This task's explicit Section 5 instruction says
"Deploy Tempo." Per this task's own instruction ("if implementation conflicts with the
blueprint, STOP and document the conflict" — not invent a silent resolution), that conflict is
recorded here rather than either quietly building Jaeger against this task's explicit
instruction, or quietly building Tempo without flagging the mismatch:

- **What was built**: Tempo (`tempo.tf`), because this task's Section 5 is an explicit, detailed,
  unambiguous instruction for this phase.
- **What the blueprint says**: Jaeger, in a section written before this phase's own detailed
  spec existed.
- **Resolution**: `docs/architecture/adr/0011-tracing-backend-tempo.md` in the backend
  repository — Accepted, supersedes `cloud-architecture-blueprint.md` Section 10. This is no
  longer an open discrepancy between two documents; the blueprint's Jaeger mention is the
  superseded state, not the current one.

## What's still a placeholder (matches this task's own scope)

- Alertmanager's Slack/PagerDuty receivers — routing/grouping/inhibition fully configured
  (`alerting-guide.md`), the actual webhook URL/integration key are empty Secrets Manager
  containers a human populates.
- Grafana SSO — `auth.generic_oauth` block present and correctly shaped, `enabled: false` until
  an IdP is chosen (`grafana-guide.md`).
- "Application Overview" dashboard and every RED-metric recording rule — correct queries, no data
  until a future phase deploys `api-gateway`/`workers` (this task's explicit "no application
  deployment" scope).
- OTLP endpoint — reachable, receives nothing until the backend's NestJS OpenTelemetry SDK
  integration (an application-code change, out of this infrastructure-only phase) is built.

## Correlation: trace ↔ log ↔ metric

Wired at the Grafana datasource level (`grafana-datasources.tf`), not via any application code:
Loki's `derivedFields` turns a `traceId` field in a log line into a clickable link into Tempo;
Tempo's `tracesToLogsV2`/`tracesToMetrics` link a trace back to its originating log lines and to
a request-rate metric query. This only produces working links once logs/traces actually carry a
shared `traceId` — which requires the same OpenTelemetry SDK integration named above.
