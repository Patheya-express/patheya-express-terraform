# Loki — S3-backed (storage.tf), TSDB index, structured-metadata-aware (Loki 3.x) so
# high-cardinality fields (requestId/correlationId/traceId/spanId — platform-standards.md
# Section 11) can travel with a log line without becoming Prometheus-style labels, which would
# blow up Loki's own index cardinality exactly the way it would Prometheus's.

locals {
  loki_replicas = local.is_production ? 2 : 1

  loki_values = {
    fullnameOverride = "loki"

    deploymentMode = var.loki_deployment_mode

    loki = {
      auth_enabled = false

      commonConfig = {
        replication_factor = local.is_production ? 2 : 1
      }

      storage = {
        type = "s3"
        s3 = {
          region           = var.aws_region
          bucketnames      = aws_s3_bucket.loki.id
          s3ForcePathStyle = false
        }
      }

      schemaConfig = {
        configs = [
          {
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "s3"
            schema       = "v13"
            index        = { prefix = "loki_index_", period = "24h" }
          }
        ]
      }

      limits_config = {
        retention_period        = "${var.loki_retention_days * 24}h"
        ingestion_rate_mb       = local.is_production ? 16 : 8
        ingestion_burst_size_mb = local.is_production ? 32 : 16
        max_query_series        = 5000
        # Structured metadata (not extra index labels) is where requestId/correlationId/traceId/
        # spanId live — keeps Loki's label cardinality bounded to namespace/pod/container/app
        # regardless of how many distinct request IDs are ever logged.
        allow_structured_metadata = true
      }

      compactor = {
        retention_enabled    = true
        delete_request_store = "s3"
      }

      serviceAccount = {
        create      = true
        name        = "loki"
        annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn }
      }
    }

    # SingleBinary (dev/staging): one component does everything — simplest operational shape at
    # low log volume. SimpleScalable (production): read/write/backend split so ingestion and
    # query load scale independently — matches the same environment-tiered-complexity pattern
    # already used for Redis (single-node dev -> cluster-mode prod) and Aurora (serverless ->
    # provisioned).
    singleBinary = {
      replicas = var.loki_deployment_mode == "SingleBinary" ? local.loki_replicas : 0
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      persistence = {
        storageClass = var.storage_class_name
        size         = "20Gi"
      }
    }

    write = {
      replicas = var.loki_deployment_mode == "SimpleScalable" ? local.loki_replicas : 0
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      persistence = { storageClass = var.storage_class_name, size = "10Gi" }
    }
    read = {
      replicas = var.loki_deployment_mode == "SimpleScalable" ? local.loki_replicas : 0
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
    }
    backend = {
      replicas = var.loki_deployment_mode == "SimpleScalable" ? local.loki_replicas : 0
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      persistence = { storageClass = var.storage_class_name, size = "10Gi" }
    }

    gateway = {
      replicas = local.loki_replicas
    }

    monitoring = {
      serviceMonitor = { enabled = true }                                        # scraped directly by the ServiceMonitor the chart creates itself — Loki's own chart supports this natively, unlike the hand-rolled addons in servicemonitors.tf
      selfMonitoring = { enabled = false, grafanaAgent = { installId = false } } # avoids the chart also trying to install its own Grafana Agent — this repo already has Promtail for log shipping
      lokiCanary     = { enabled = false }
    }

    test = { enabled = false }
  }

  promtail_values = {
    fullnameOverride = "promtail"

    config = {
      clients = [
        { url = "http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push" }
      ]
      # Parses the JSON structure Phase 1A's Winston logger already emits
      # (timestamp/level/message/context/requestId/correlationId) and promotes only
      # low-cardinality fields (namespace/pod/container, already added by Promtail's own
      # Kubernetes service discovery relabeling) to Loki labels — requestId/correlationId ride
      # as structured metadata instead (loki.limits_config.allow_structured_metadata above).
      snippets = {
        pipelineStages = [
          { cri = {} },
          {
            json = {
              expressions = {
                level         = "level"
                requestId     = "requestId"
                correlationId = "correlationId"
                traceId       = "traceId"
              }
            }
          },
          { labels = { level = "" } },
          {
            structured_metadata = {
              requestId     = ""
              correlationId = ""
              traceId       = ""
            }
          },
        ]
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "200m", memory = "256Mi" }
    }

    serviceMonitor = { enabled = true }

    tolerations = [
      { operator = "Exists" } # Promtail is a DaemonSet — it must run on every node, including tainted ones, to actually collect every pod's logs
    ]
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = "logging"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.20.0"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.loki_values)]

  depends_on = [kubernetes_resource_quota_v1.logging]
}

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = "logging"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"
  wait       = true
  atomic     = true

  values = [yamlencode(local.promtail_values)]

  depends_on = [helm_release.loki]
}
