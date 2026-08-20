# Grafana's datasource sidecar (prometheus-stack.tf's grafana.sidecar.datasources) auto-loads any
# ConfigMap in the "monitoring" namespace labeled grafana_datasource=1 — datasource changes are a
# ConfigMap update the sidecar picks up live, never a Helm upgrade (platform-standards.md Section
# 12: "a Grafana JSON model is committed ... not click-configured").

resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = "monitoring"
    labels    = { grafana_datasource = "1" }
  }

  data = {
    "datasources.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        {
          name      = "Prometheus"
          type      = "prometheus"
          uid       = "prometheus"
          access    = "proxy"
          url       = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
          isDefault = true
          jsonData  = { timeInterval = "30s" }
        },
        {
          name   = "Alertmanager"
          type   = "alertmanager"
          access = "proxy"
          url    = "http://kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093"
          jsonData = {
            implementation = "prometheus"
          }
        },
        {
          name   = "Loki"
          type   = "loki"
          uid    = "loki"
          access = "proxy"
          url    = "http://loki-gateway.logging.svc.cluster.local"
          jsonData = {
            # Log -> trace correlation (this task's Section 11): a traceId structured-metadata
            # field (loki.tf's promtail pipeline) becomes a clickable link straight into Tempo.
            derivedFields = [
              {
                datasourceUid = "tempo"
                matcherRegex  = "traceId=(\\w+)"
                name          = "TraceID"
                url           = "$${__value.raw}"
              }
            ]
          }
        },
        {
          name   = "Tempo"
          type   = "tempo"
          uid    = "tempo"
          access = "proxy"
          url    = "http://tempo.tracing.svc.cluster.local:3100"
          jsonData = {
            # Trace -> logs and trace -> metrics correlation (this task's Section 11) —
            # completes the loop Loki's derivedFields above starts in the other direction.
            tracesToLogsV2 = {
              datasourceUid      = "loki"
              spanStartTimeShift = "-5m"
              spanEndTimeShift   = "5m"
              filterByTraceID    = true
            }
            tracesToMetrics = {
              datasourceUid = "prometheus"
              queries = [
                {
                  name  = "Request rate"
                  query = "sum(rate(patheya_http_requests_total{$$__tags}[5m]))"
                }
              ]
            }
            serviceMap = { datasourceUid = "prometheus" }
          }
        },
        {
          name   = "CloudWatch"
          type   = "cloudwatch"
          uid    = "cloudwatch"
          access = "proxy"
          jsonData = {
            authType      = "default" # IRSA (iam.tf's grafana role), not static keys
            defaultRegion = var.aws_region
          }
        },
      ]
    })
  }
}
