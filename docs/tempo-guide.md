# Tempo guide

`tempo.tf` — S3-backed trace storage, metrics-generator on, native TraceQL search. See
`docs/observability-guide.md`'s documented-conflicts section for why Tempo, not the blueprint's
Jaeger mention.

## Storage and retention

S3-backed (`storage.tf`'s bucket, IRSA-scoped identically to Loki's pattern). Retention: 72h
(development) / 120h (staging) / 168h — 7 days — (production). Traces are far higher-volume per
byte-of-signal than logs; a week is already generous compared to typical production tracing
retention (many shops run 24–72h) — chosen deliberately shorter than Loki's log retention rather
than matching it 1:1.

## Metrics generation

`metricsGenerator.enabled: true`, remote-writing RED metrics (service graphs + span metrics)
derived from actual trace data into the same in-cluster Prometheus every other component uses.
This is genuinely a second, independent source of RED metrics from the OpenTelemetry Collector's
own metrics pipeline (`otel-guide.md`) — Tempo derives metrics from spans it already stores;
the Collector's metrics pipeline handles metrics an application emits directly via OTLP. They
overlap in intent (both eventually produce request-rate/error-rate/duration series) but arrive
by different paths and neither depends on the other being correctly configured.

## Trace search

TraceQL, Tempo's native query language — enabled by default with an S3-backed deployment (no
extra component, unlike some Jaeger deployment topologies that need a separate query/search
service). Reachable from Grafana's Tempo datasource (`grafana-datasources.tf`) — the "Search"
tab in Grafana's Explore view against the Tempo datasource.

## OTLP endpoint

`tempo.tracing.svc.cluster.local:4317` (gRPC) — this is what the OpenTelemetry Collector's traces
exporter (`otel-collector.tf`) sends to. Application code never talks to Tempo directly; it always
goes through the Collector.

## What's not built yet

The actual application-side trace generation — NestJS's OpenTelemetry SDK integration
(`cloud-architecture-blueprint.md` Section 10) is application code, explicitly out of this
infrastructure-only phase. Tempo has a real, working ingestion path and nothing to ingest yet.
