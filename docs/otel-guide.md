# OpenTelemetry Collector guide

`otel-collector.tf` — one `Deployment` (gateway mode, not a per-node DaemonSet — Promtail already
owns node-level log collection) in the new `observability` namespace.

## Why "deployment" mode, not "daemonset"

Two valid OpenTelemetry Collector topologies exist: a DaemonSet (one collector per node, typically
for node-level metrics/logs) and a Deployment (a central gateway application code sends telemetry
to over the network). This platform's actual need — a single OTLP endpoint the future NestJS SDK
integration sends traces/metrics/logs to — is exactly the gateway shape, and node-level log
collection is already Promtail's job. Running both a DaemonSet Collector and Promtail on every
node would be redundant.

## Pipelines

| Pipeline | Receivers | Processors | Exporters |
| --- | --- | --- | --- |
| Traces | OTLP (gRPC :4317, HTTP :4318) | memory_limiter → k8sattributes → resource → probabilistic_sampler → batch | Tempo (OTLP) |
| Metrics | OTLP | memory_limiter → k8sattributes → resource → batch | Prometheus (remote-write) |
| Logs | OTLP | memory_limiter → k8sattributes → resource → batch | Loki |

The logs pipeline exists for OTLP-native log signals specifically (an SDK that emits logs via
OTLP rather than stdout) — it does **not** replace Promtail's stdout-JSON-log collection path;
both exist because they serve different emission mechanisms an application might use.

## k8sattributes — why a ClusterRole, not IRSA

This processor enriches every span/metric/log with pod/namespace/deployment metadata by watching
the Kubernetes API — a Kubernetes RBAC concern (`clusterRole` in the Helm values), not an AWS IAM
one. The Collector calls no AWS API of its own; everything it exports to (Tempo, Prometheus,
Loki) already has its own IRSA role for its own AWS calls (S3, in Tempo/Loki's case).

## Sampling

Head-based probabilistic sampling (`probabilistic_sampler` processor), not tail-based. Ratio:
100% in development/staging (full visibility while the application and its instrumentation are
still new and unproven), 20% in production (`otel_sampling_ratio` — controls cost/volume once
real traffic and trace volume exist). This is a policy choice, documented here, not a default
left unexamined — revisit the production ratio once real trace volume data exists to size it
against (Phase 8's load-testing phase is the natural point to revisit).

## Endpoint

`otel-collector.observability.svc.cluster.local:4317` — the literal value a future NestJS
`@opentelemetry/exporter-trace-otlp-grpc` (or equivalent) configuration would point
`OTEL_EXPORTER_OTLP_ENDPOINT` at. Nothing sends real telemetry here yet — that SDK integration is
application code, out of this infrastructure-only phase's scope
(`cloud-architecture-blueprint.md` Section 4's "Phase 4" app-code items note the same boundary for
a different pair of features; this is the observability-phase analog).
