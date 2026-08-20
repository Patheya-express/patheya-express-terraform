# 11 dashboards (this task's Section 13), organized into 3 Grafana folders via the
# grafana_folder annotation the dashboard sidecar reads (prometheus-stack.tf). Every dashboard
# here queries real metric names already emitted by something this platform has actually
# installed (kube-state-metrics/node-exporter for K8s dashboards, CloudWatch for Aurora/Redis,
# PgBouncer's own exporter, ingress-nginx's standard metrics) — the one deliberate exception is
# "Application Overview", which this task's Section 13 explicitly asks to leave as an empty
# placeholder (queries wired to patheya_* metric names that show "No data" until a future phase
# deploys the application that emits them).
#
# Every panel object below shares one uniform schema (title/type/datasource/query/unit/
# cw_namespace/cw_metric/cw_stat), with unused fields left null — HCL requires every value in a
# map/list literal to unify to a single type, so a Prometheus panel and a CloudWatch panel must
# have the same attribute set even though each only uses half of it.

locals {
  grafana_folder_infra = "Infrastructure"
  grafana_folder_data  = "Data Platform"
  grafana_folder_app   = "Applications"

  dashboard_defaults = {
    schemaVersion = 39
    timezone      = "utc"
    refresh       = "30s"
    time          = { from = "now-6h", to = "now" }
    tags          = ["patheya-express", "terraform-managed"]
  }

  dashboards = {
    cluster-overview = {
      title  = "Cluster Overview"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Node count (Ready)", type = "stat", datasource = "prometheus", query = "count(kube_node_status_condition{condition=\"Ready\", status=\"true\"})", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Cluster CPU utilization", type = "timeseries", datasource = "prometheus", query = "avg(patheya:node_cpu_utilization:ratio) * 100", unit = "percent", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Cluster memory utilization", type = "timeseries", datasource = "prometheus", query = "avg(patheya:node_memory_utilization:ratio) * 100", unit = "percent", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Pods running by namespace", type = "timeseries", datasource = "prometheus", query = "sum(kube_pod_status_phase{phase=\"Running\"}) by (namespace)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Karpenter-managed nodes (on-demand vs spot)", type = "timeseries", datasource = "prometheus", query = "count(kube_node_labels) by (label_karpenter_sh_capacity_type)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Pods pending (unschedulable)", type = "stat", datasource = "prometheus", query = "sum(kube_pod_status_phase{phase=\"Pending\"})", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    kubernetes-health = {
      title  = "Kubernetes Health"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Deployment replica mismatch (desired vs available)", type = "timeseries", datasource = "prometheus", query = "sum(kube_deployment_spec_replicas - kube_deployment_status_replicas_available) by (namespace, deployment)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "CrashLoopBackOff pods", type = "timeseries", datasource = "prometheus", query = "sum(kube_pod_container_status_waiting_reason{reason=\"CrashLoopBackOff\"}) by (namespace, pod)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Container restarts (1h)", type = "timeseries", datasource = "prometheus", query = "sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "PodDisruptionBudgets — disruptions allowed", type = "timeseries", datasource = "prometheus", query = "kube_poddisruptionbudget_status_disruptions_allowed", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "HPA current vs desired replicas", type = "timeseries", datasource = "prometheus", query = "kube_horizontalpodautoscaler_status_current_replicas", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "ResourceQuota usage by namespace", type = "timeseries", datasource = "prometheus", query = "kube_resourcequota{type=\"used\"} / kube_resourcequota{type=\"hard\"}", unit = "percentunit", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    node-health = {
      title  = "Node Health"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Per-node CPU utilization", type = "timeseries", datasource = "prometheus", query = "patheya:node_cpu_utilization:ratio * 100", unit = "percent", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Per-node memory utilization", type = "timeseries", datasource = "prometheus", query = "patheya:node_memory_utilization:ratio * 100", unit = "percent", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Disk pressure condition", type = "timeseries", datasource = "prometheus", query = "kube_node_status_condition{condition=\"DiskPressure\", status=\"true\"}", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Node filesystem usage", type = "timeseries", datasource = "prometheus", query = "1 - (node_filesystem_avail_bytes{fstype!=\"\"} / node_filesystem_size_bytes{fstype!=\"\"})", unit = "percentunit", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Network receive/transmit bytes", type = "timeseries", datasource = "prometheus", query = "rate(node_network_receive_bytes_total[5m])", unit = "Bps", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    application-overview = {
      title  = "Application Overview"
      folder = local.grafana_folder_app
      # Deliberately a placeholder shape — this task's Section 13 explicitly asks for this one
      # dashboard to stay empty until a future phase deploys api-gateway/workers. Every query
      # below is correct and ready; none has any series to return yet.
      panels = [
        { title = "Request rate (api-gateway)", type = "timeseries", datasource = "prometheus", query = "patheya:http_requests:rate5m{app=\"api-gateway\"}", unit = "reqps", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Error rate (api-gateway)", type = "timeseries", datasource = "prometheus", query = "patheya:http_requests_errors:rate5m{app=\"api-gateway\"}", unit = "reqps", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "p95 latency (api-gateway)", type = "timeseries", datasource = "prometheus", query = "patheya:http_request_duration_seconds:p95_5m{app=\"api-gateway\"}", unit = "s", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "BullMQ queue depth", type = "timeseries", datasource = "prometheus", query = "patheya:bullmq_queue_depth:current", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    aurora = {
      title  = "Aurora"
      folder = local.grafana_folder_data
      panels = [
        { title = "Writer CPU utilization", type = "timeseries", datasource = "cloudwatch", query = null, unit = "percent", cw_namespace = "AWS/RDS", cw_metric = "CPUUtilization", cw_stat = "Average" },
        { title = "Freeable memory", type = "timeseries", datasource = "cloudwatch", query = null, unit = "bytes", cw_namespace = "AWS/RDS", cw_metric = "FreeableMemory", cw_stat = "Average" },
        { title = "Database connections", type = "timeseries", datasource = "cloudwatch", query = null, unit = "short", cw_namespace = "AWS/RDS", cw_metric = "DatabaseConnections", cw_stat = "Average" },
        { title = "Reader replica lag", type = "timeseries", datasource = "cloudwatch", query = null, unit = "ms", cw_namespace = "AWS/RDS", cw_metric = "AuroraReplicaLag", cw_stat = "Maximum" },
        { title = "Read IOPS", type = "timeseries", datasource = "cloudwatch", query = null, unit = "iops", cw_namespace = "AWS/RDS", cw_metric = "ReadIOPS", cw_stat = "Sum" },
      ]
    }

    redis = {
      title  = "Redis"
      folder = local.grafana_folder_data
      panels = [
        { title = "Engine CPU utilization", type = "timeseries", datasource = "cloudwatch", query = null, unit = "percent", cw_namespace = "AWS/ElastiCache", cw_metric = "EngineCPUUtilization", cw_stat = "Average" },
        { title = "Memory usage", type = "timeseries", datasource = "cloudwatch", query = null, unit = "percent", cw_namespace = "AWS/ElastiCache", cw_metric = "DatabaseMemoryUsagePercentage", cw_stat = "Average" },
        { title = "Current connections", type = "timeseries", datasource = "cloudwatch", query = null, unit = "short", cw_namespace = "AWS/ElastiCache", cw_metric = "CurrConnections", cw_stat = "Average" },
        { title = "Evictions", type = "timeseries", datasource = "cloudwatch", query = null, unit = "short", cw_namespace = "AWS/ElastiCache", cw_metric = "Evictions", cw_stat = "Sum" },
        { title = "Replication lag", type = "timeseries", datasource = "cloudwatch", query = null, unit = "s", cw_namespace = "AWS/ElastiCache", cw_metric = "ReplicationLag", cw_stat = "Maximum" },
      ]
    }

    pgbouncer = {
      title  = "PgBouncer"
      folder = local.grafana_folder_data
      panels = [
        { title = "Active client connections", type = "timeseries", datasource = "prometheus", query = "pgbouncer_pools_client_active_connections", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Active server connections", type = "timeseries", datasource = "prometheus", query = "pgbouncer_pools_server_active_connections", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Waiting clients", type = "timeseries", datasource = "prometheus", query = "pgbouncer_pools_client_waiting_connections", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Server connections (patheya_write pool)", type = "timeseries", datasource = "prometheus", query = "pgbouncer_pools_server_active_connections{database=\"patheya_write\"}", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Average query duration", type = "timeseries", datasource = "prometheus", query = "rate(pgbouncer_stats_query_time_seconds_total[5m]) / rate(pgbouncer_stats_queries_total[5m])", unit = "s", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    ingress = {
      title  = "Ingress"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Request rate (NGINX)", type = "timeseries", datasource = "prometheus", query = "sum(rate(nginx_ingress_controller_requests[5m])) by (ingress)", unit = "reqps", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Request duration p95 (NGINX)", type = "timeseries", datasource = "prometheus", query = "histogram_quantile(0.95, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (ingress, le))", unit = "s", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "5xx response rate (NGINX)", type = "timeseries", datasource = "prometheus", query = "sum(rate(nginx_ingress_controller_requests{status=~\"5..\"}[5m])) by (ingress)", unit = "reqps", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "AWS LB Controller reconcile errors", type = "timeseries", datasource = "prometheus", query = "sum(rate(controller_runtime_reconcile_errors_total[5m])) by (controller)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "ExternalDNS sync errors", type = "timeseries", datasource = "prometheus", query = "sum(rate(external_dns_registry_errors_total[5m]))", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    networking = {
      title  = "Networking"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Node network transmit errors", type = "timeseries", datasource = "prometheus", query = "sum(rate(node_network_transmit_errs_total[5m])) by (node)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "CoreDNS query rate", type = "timeseries", datasource = "prometheus", query = "sum(rate(coredns_dns_requests_total[5m])) by (zone)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "CoreDNS request duration p95", type = "timeseries", datasource = "prometheus", query = "histogram_quantile(0.95, sum(rate(coredns_dns_request_duration_seconds_bucket[5m])) by (le))", unit = "s", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    storage = {
      title  = "Storage"
      folder = local.grafana_folder_infra
      panels = [
        { title = "PVC utilization", type = "timeseries", datasource = "prometheus", query = "patheya:pvc_utilization:ratio * 100", unit = "percent", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "EBS CSI volume create errors", type = "timeseries", datasource = "prometheus", query = "sum(rate(csi_operations_seconds_count{operation_name=\"CreateVolume\", grpc_status_code!=\"OK\"}[15m]))", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Bound vs unbound PVCs", type = "timeseries", datasource = "prometheus", query = "count(kube_persistentvolumeclaim_status_phase) by (phase)", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }

    certificates = {
      title  = "Certificates"
      folder = local.grafana_folder_infra
      panels = [
        { title = "Days until expiry", type = "timeseries", datasource = "prometheus", query = "(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400", unit = "d", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "Certificate ready status", type = "timeseries", datasource = "prometheus", query = "certmanager_certificate_ready_status{condition=\"True\"}", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
        { title = "ACME order failures", type = "timeseries", datasource = "prometheus", query = "sum(rate(certmanager_acme_client_request_count{status!~\"2..\"}[15m]))", unit = "short", cw_namespace = null, cw_metric = null, cw_stat = null },
      ]
    }
  }

  # Builds each dashboard's full Grafana JSON model from the uniform panel descriptions above.
  dashboard_json = {
    for key, d in local.dashboards : key => jsonencode(merge(local.dashboard_defaults, {
      title = d.title
      uid   = "patheya-${key}"
      panels = [
        # A single, non-branching object shape for every panel — both datasource types populate
        # the same target/datasource attribute set (unused fields null), since HCL's conditional
        # expression requires both outcomes of a "true ? {} : {}" to unify to one type, and a
        # CloudWatch target's extra "dimensions"/"namespace"/"statistic" fields would otherwise
        # never unify with a Prometheus target's bare "expr" field.
        for idx, p in d.panels : {
          id      = idx
          title   = p.title
          type    = p.type
          gridPos = { h = 8, w = 12, x = (idx % 2) * 12, y = floor(idx / 2) * 8 }
          datasource = {
            type = p.datasource
            uid  = p.datasource
          }
          targets = [{
            refId      = "A"
            expr       = p.datasource == "cloudwatch" ? null : p.query
            namespace  = p.datasource == "cloudwatch" ? p.cw_namespace : null
            metricName = p.datasource == "cloudwatch" ? p.cw_metric : null
            statistic  = p.datasource == "cloudwatch" ? p.cw_stat : null
            region     = p.datasource == "cloudwatch" ? var.aws_region : null
            dimensions = p.datasource == "cloudwatch" ? {
              DBClusterIdentifier = "${var.name_prefix}-aurora"
              CacheClusterId      = "${var.name_prefix}-redis"
            } : null
          }]
          fieldConfig = { defaults = { unit = p.unit } }
        }
      ]
    }))
  }
}

resource "kubernetes_config_map_v1" "grafana_dashboard" {
  for_each = local.dashboards

  metadata {
    name      = "grafana-dashboard-${each.key}"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
    annotations = {
      grafana_folder = each.value.folder
    }
  }

  data = {
    "${each.key}.json" = local.dashboard_json[each.key]
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
