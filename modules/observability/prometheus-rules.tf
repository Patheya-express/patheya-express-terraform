# Recording rules (RED for the future application, USE for infrastructure that already exists
# and already has real data) + SLO burn-rate alerts + infrastructure alert rules. Alert naming
# throughout follows platform-standards.md Section 12's <Severity>-<Service>-<Condition>
# convention exactly.

resource "kubernetes_manifest" "recording_rules_red" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "patheya-red-recording-rules"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          name     = "patheya.red.rules"
          interval = "30s"
          rules = [
            # RED (Rate/Errors/Duration) for api-gateway — no data until the application exists
            # and emits patheya_http_requests_total/patheya_http_request_duration_seconds
            # (platform-standards.md Section 12's metric-naming convention); the rules themselves
            # are correct and ready the moment it does (this task's Section 9).
            {
              record = "patheya:http_requests:rate5m"
              expr   = "sum(rate(patheya_http_requests_total[5m])) by (namespace, app, status)"
            },
            {
              record = "patheya:http_requests_errors:rate5m"
              expr   = "sum(rate(patheya_http_requests_total{status=~\"5..\"}[5m])) by (namespace, app)"
            },
            {
              record = "patheya:http_request_duration_seconds:p95_5m"
              expr   = "histogram_quantile(0.95, sum(rate(patheya_http_request_duration_seconds_bucket[5m])) by (namespace, app, le))"
            },
            {
              record = "patheya:http_request_duration_seconds:p99_5m"
              expr   = "histogram_quantile(0.99, sum(rate(patheya_http_request_duration_seconds_bucket[5m])) by (namespace, app, le))"
            },
            {
              record = "patheya:bullmq_queue_depth:current"
              expr   = "max(patheya_bullmq_queue_depth) by (namespace, queue)"
            },
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "recording_rules_use" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "patheya-use-recording-rules"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          # USE (Utilization/Saturation/Errors) for infrastructure that already exists — real
          # data immediately, sourced from node-exporter/kube-state-metrics (both enabled in
          # prometheus-stack.tf).
          name     = "patheya.use.rules"
          interval = "30s"
          rules = [
            {
              record = "patheya:node_cpu_utilization:ratio"
              expr   = "1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) by (node)"
            },
            {
              record = "patheya:node_memory_utilization:ratio"
              expr   = "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
            },
            {
              record = "patheya:pod_cpu_saturation:ratio"
              expr   = "sum(rate(container_cpu_cfs_throttled_periods_total[5m])) by (namespace, pod) / sum(rate(container_cpu_cfs_periods_total[5m])) by (namespace, pod)"
            },
            {
              record = "patheya:pvc_utilization:ratio"
              expr   = "1 - (kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes)"
            },
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# --- SLO burn-rate alerts (cloud-architecture-blueprint.md Section 10's three named SLOs) -------
#
# Standard 2-window multi-burn-rate pattern (Google SRE Workbook) — a short window catches fast
# burns quickly with a higher burn-rate threshold (noisier but faster to page on), a long window
# confirms the burn is sustained, not a blip, before Critical actually pages. No data until the
# application exists and emits the underlying metrics — same "prepare, don't require the app"
# posture as the RED recording rules above.
resource "kubernetes_manifest" "slo_burn_rate_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "patheya-slo-burn-rate-alerts"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          name = "patheya.slo.api-availability"
          rules = [
            {
              # 99.9% monthly SLO -> 0.1% error budget. 14.4x burn rate over 5m+1h exhausts the
              # whole month's budget in ~2 days if sustained — the "fast burn" page.
              alert  = "Critical-ApiGateway-SLOBurnRateFast"
              expr   = <<-EOT
                (
                  patheya:http_requests_errors:rate5m / patheya:http_requests:rate5m > (14.4 * 0.001)
                )
                and
                (
                  sum(rate(patheya_http_requests_total{status=~"5.."}[1h])) / sum(rate(patheya_http_requests_total[1h])) > (14.4 * 0.001)
                )
              EOT
              for    = "2m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "api-gateway error budget burning >14.4x — 99.9% monthly SLO exhausted in ~2 days at this rate"
                description = "cloud-architecture-blueprint.md Section 10's API availability SLO (99.9%/month) is burning fast. Check recent deploys and the error-rate dashboard first."
              }
            },
            {
              # 6x burn rate over 30m+6h — the "slow burn" warning, catches a sustained-but-less-
              # dramatic degradation the fast-burn window alone would miss.
              alert  = "Warning-ApiGateway-SLOBurnRateSlow"
              expr   = <<-EOT
                (
                  sum(rate(patheya_http_requests_total{status=~"5.."}[30m])) / sum(rate(patheya_http_requests_total[30m])) > (6 * 0.001)
                )
                and
                (
                  sum(rate(patheya_http_requests_total{status=~"5.."}[6h])) / sum(rate(patheya_http_requests_total[6h])) > (6 * 0.001)
                )
              EOT
              for    = "15m"
              labels = { severity = "warning" }
              annotations = {
                summary     = "api-gateway error budget burning >6x — sustained, not yet critical"
                description = "A slower but sustained SLO burn — investigate before it escalates to Critical-ApiGateway-SLOBurnRateFast."
              }
            },
          ]
        },
        {
          name = "patheya.slo.order-creation-latency"
          rules = [
            {
              # p95 < 300ms SLO (blueprint Section 10) — alerts on the recording rule already
              # computing p95, not a raw histogram_quantile inline, to keep this rule cheap.
              alert  = "Critical-ApiGateway-OrderCreationLatencyHigh"
              expr   = "patheya:http_request_duration_seconds:p95_5m{app=\"api-gateway\"} > 0.3"
              for    = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "Order creation p95 latency above 300ms SLO for 5+ minutes"
                description = "cloud-architecture-blueprint.md Section 10's order-creation latency SLO (p95 < 300ms) is breached."
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "infrastructure_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "patheya-infrastructure-alerts"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          name = "patheya.infrastructure"
          rules = [
            {
              alert       = "Critical-Node-NotReady"
              expr        = "kube_node_status_condition{condition=\"Ready\", status=\"true\"} == 0"
              for         = "5m"
              labels      = { severity = "critical" }
              annotations = { summary = "Node {{ $labels.node }} has been NotReady for 5+ minutes" }
            },
            {
              alert       = "Warning-Node-CPUUtilizationHigh"
              expr        = "patheya:node_cpu_utilization:ratio > 0.85"
              for         = "10m"
              labels      = { severity = "warning" }
              annotations = { summary = "Node {{ $labels.node }} CPU utilization above 85% for 10+ minutes" }
            },
            {
              alert       = "Critical-Pod-CrashLoopBackOff"
              expr        = "kube_pod_container_status_waiting_reason{reason=\"CrashLoopBackOff\"} == 1"
              for         = "5m"
              labels      = { severity = "critical" }
              annotations = { summary = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is CrashLoopBackOff" }
            },
            {
              alert       = "Warning-PVC-NearlyFull"
              expr        = "patheya:pvc_utilization:ratio > 0.85"
              for         = "10m"
              labels      = { severity = "warning" }
              annotations = { summary = "PersistentVolumeClaim {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} above 85% full" }
            },
            {
              alert       = "Critical-PVC-AlmostFull"
              expr        = "patheya:pvc_utilization:ratio > 0.95"
              for         = "5m"
              labels      = { severity = "critical" }
              annotations = { summary = "PersistentVolumeClaim {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} above 95% full — imminent write failures" }
            },
            {
              alert       = "Warning-Karpenter-NodeProvisioningFailed"
              expr        = "increase(karpenter_nodeclaims_disrupted_total{reason=\"expired\"}[15m]) > 0"
              for         = "0m"
              labels      = { severity = "warning" }
              annotations = { summary = "Karpenter node provisioning/disruption events in the last 15 minutes — check Karpenter controller logs (Loki, namespace kube-system)" }
            },
            {
              alert       = "Warning-Certificate-ExpiringSoon"
              expr        = "certmanager_certificate_expiration_timestamp_seconds - time() < 7 * 86400"
              for         = "1h"
              labels      = { severity = "warning" }
              annotations = { summary = "cert-manager certificate {{ $labels.namespace }}/{{ $labels.name }} expires within 7 days" }
            },
            {
              alert       = "Critical-Certificate-Expired"
              expr        = "certmanager_certificate_expiration_timestamp_seconds - time() < 0"
              for         = "0m"
              labels      = { severity = "critical" }
              annotations = { summary = "cert-manager certificate {{ $labels.namespace }}/{{ $labels.name }} has expired" }
            },
            {
              alert       = "Warning-Worker-JobFailed"
              expr        = "increase(patheya_bullmq_jobs_failed_total[15m]) > 0"
              for         = "0m"
              labels      = { severity = "warning" }
              annotations = { summary = "BullMQ queue {{ $labels.queue }} has failed jobs in the last 15 minutes — platform-standards.md Section 17's dead-letter policy: review and retry/discard manually" }
            },
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
