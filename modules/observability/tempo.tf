# Tempo — S3-backed trace storage (storage.tf), metrics-generator on (spans -> RED metrics,
# remote-written into kube-prometheus-stack's Prometheus), native TraceQL search.
#
# Chosen over the blueprint's Section 10 mention of Jaeger — see the Phase 5 final report's
# documented-conflicts section for why this is treated as a deliberate, explicit instruction
# from this task rather than silently implemented against the blueprint or silently substituted
# back to Jaeger without telling you.

locals {
  tempo_replicas = local.is_production ? 2 : 1

  tempo_values = {
    fullnameOverride = "tempo"

    tempo = {
      repository = "grafana/tempo"

      storage = {
        trace = {
          backend = "s3"
          s3 = {
            bucket   = aws_s3_bucket.tempo.id
            region   = var.aws_region
            endpoint = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      }

      retention = "${var.tempo_retention_hours}h"

      # Spans -> RED metrics (request rate, error rate, duration histograms), written into
      # Prometheus via remote-write to the in-cluster Prometheus Service — this is Tempo's own
      # "Metrics generation" (this task's Section 5), independent of and complementary to
      # anything the OpenTelemetry Collector's own metrics pipeline produces (otel-collector.tf).
      metricsGenerator = {
        enabled        = true
        remoteWriteUrl = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
        processor = {
          serviceGraphs = { enabled = true }
          spanMetrics   = { enabled = true }
        }
      }

      serviceAccount = {
        create      = true
        name        = "tempo"
        annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.tempo.arn }
      }

      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
    }

    replicas = local.tempo_replicas

    persistence = {
      enabled          = true
      storageClassName = var.storage_class_name
      size             = "10Gi"
    }

    serviceMonitor = { enabled = true }

    # OTLP gRPC (4317) / HTTP (4318) receivers — this is the endpoint the OpenTelemetry
    # Collector's traces exporter (otel-collector.tf) sends to, not something application code
    # talks to directly (docs/otel-guide.md).
  }
}

resource "helm_release" "tempo" {
  name       = "tempo"
  namespace  = "tracing"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.16.1"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.tempo_values)]

  depends_on = [kubernetes_resource_quota_v1.tracing]
}
