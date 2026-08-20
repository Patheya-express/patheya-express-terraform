# modules/observability

Prometheus, Grafana, Alertmanager (via `kube-prometheus-stack`), Loki + Promtail, Tempo, and the
OpenTelemetry Collector — called from `environments/<env>/platform/main.tf` alongside
`module.eks_addons` (same Terraform state, same `kubernetes`/`helm` provider configuration; no
new state, no new bootstrapping problem — this module needs exactly the same OIDC/cluster inputs
`eks_addons` already receives).

## Namespace ownership

`monitoring`/`logging`/`tracing` are **not** created here — they already exist, created empty by
Phase 3's `modules/eks-addons/namespaces.tf` specifically so this phase wouldn't need to also own
their lifecycle. This module only adds `ResourceQuota`/`LimitRange` to them (they didn't need one
while empty; they do now that they host real workloads — the same precedent Phase 4 set for
`data-platform`). `observability` (for the OpenTelemetry Collector) is the one genuinely new
namespace this module creates.

## File map

| File | Contents |
| --- | --- |
| `namespaces.tf` | The `observability` namespace + quotas for all 4 |
| `storage.tf` | S3 buckets (Loki, Tempo), encrypted, lifecycle-managed |
| `iam.tf` | IRSA: Loki (S3), Tempo (S3), Grafana (read-only CloudWatch) |
| `secrets.tf` | Grafana admin credential (Terraform-generated, synced via Phase 4's existing ClusterSecretStore) |
| `alertmanager-secrets.tf` | Syncs the two placeholder Slack/PagerDuty secrets (created in platform/main.tf) into the Kubernetes Secrets Alertmanager mounts |
| `prometheus-stack.tf` | `kube-prometheus-stack` — Prometheus, Alertmanager (+ routing config), Grafana |
| `loki.tf` | Loki + Promtail |
| `tempo.tf` | Tempo (see the file's own comment on why Tempo, not the blueprint's Jaeger mention) |
| `otel-collector.tf` | OpenTelemetry Collector — OTLP gateway for the not-yet-built application-code SDK integration |
| `servicemonitors.tf` | Activates scraping for every metrics endpoint Phase 3/4 already exposed but nothing was scraping yet |
| `prometheus-rules.tf` | RED/USE recording rules, SLO burn-rate alerts, infrastructure alerts |
| `grafana-datasources.tf` | Prometheus/Loki/Tempo/Alertmanager/CloudWatch, with trace↔log↔metric correlation wired |
| `grafana-dashboards.tf` | 11 dashboards (this phase's Section 13) |

## Why Helm values are HCL objects + `yamlencode()`, not `.tpl` string templates

Alertmanager's routing tree and the dashboard JSON models are deeply nested with arrays of
objects — exactly the shape that's fragile as hand-indented YAML-in-a-string and reliable as
native HCL, type-checked by `terraform validate` before it ever becomes YAML/JSON text.

## Grafana is stateless

`persistence.enabled = false` — every datasource, dashboard, and folder is provisioned from this
module's own ConfigMaps, picked up live by Grafana's sidecar containers. A dashboard created by
hand in the Grafana UI does not survive a pod restart. This is a deliberate GitOps-purity
decision (platform-standards.md Section 12), not an oversight — see `docs/grafana-guide.md`.

## What still needs a human

- `docs/alerting-guide.md`'s exact `aws secretsmanager put-secret-value` commands for the Slack
  webhook and PagerDuty integration key (both empty containers today, matching this task's
  explicit "Slack (placeholder only), PagerDuty (placeholder only)").
- Choosing and wiring a real IdP for Grafana's `auth.generic_oauth` block (currently
  `enabled: false`, SSO-ready but not SSO-active).
