# kube-prometheus-stack — Prometheus, Alertmanager, Grafana (bundled subchart), Prometheus
# Operator (ServiceMonitor/PodMonitor/PrometheusRule/Probe CRDs + admission webhooks),
# node-exporter, kube-state-metrics. One helm_release, values built as an HCL object and
# yamlencode()'d rather than a string template — Alertmanager's routing tree (nested
# routes/receivers/inhibit_rules) is exactly the kind of structure that's fragile as hand-indented
# YAML-in-a-template-string and reliable as native HCL.

locals {
  # is_production is defined once, in namespaces.tf — every other file in this module reuses it.
  prometheus_resources = local.is_production ? {
    cpu_request = "500m", memory_request = "2Gi", cpu_limit = "2", memory_limit = "4Gi"
    } : {
    cpu_request = "250m", memory_request = "1Gi", cpu_limit = "1", memory_limit = "2Gi"
  }

  # Alertmanager routing tree — platform-standards.md Section 12's three severity tiers
  # (Critical/Warning/Info), each routed to a distinct receiver. Slack/PagerDuty receivers read
  # their webhook URL / integration key from a *file*, mounted from a Kubernetes Secret
  # (alertmanager-secrets.tf's ExternalSecrets) — never an inline plaintext value in this values
  # object, which would otherwise land in the Helm release's stored values (and this module's
  # Terraform state) in cleartext even though the underlying credential is still a placeholder at
  # apply time.
  alertmanager_config = {
    global = {
      resolve_timeout = "5m"
    }
    route = {
      receiver        = "null-receiver"
      group_by        = ["alertname", "namespace", "severity"]
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
      routes = [
        {
          matchers = ["severity=\"critical\""]
          receiver = "pagerduty-critical"
          continue = false
        },
        {
          matchers = ["severity=\"warning\""]
          receiver = "slack-warnings"
          continue = false
        },
        {
          matchers = ["severity=\"info\""]
          receiver = "null-receiver"
          continue = false
        },
      ]
    }
    inhibit_rules = [
      {
        source_matchers = ["severity=\"critical\""]
        target_matchers = ["severity=\"warning\""]
        equal           = ["alertname", "namespace"]
      }
    ]
    receivers = [
      { name = "null-receiver" },
      {
        name = "pagerduty-critical"
        pagerduty_configs = [
          {
            service_key_file = "/etc/alertmanager/secrets/alertmanager-pagerduty-key/key"
            send_resolved    = true
          }
        ]
      },
      {
        name = "slack-warnings"
        slack_configs = [
          {
            api_url_file  = "/etc/alertmanager/secrets/alertmanager-slack-webhook/webhook-url"
            channel       = "#patheya-alerts"
            send_resolved = true
            title         = "{{ .CommonLabels.alertname }}"
            text          = "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"
          }
        ]
      },
    ]
  }

  kube_prometheus_stack_values = {
    fullnameOverride = "kube-prometheus-stack"

    prometheus = {
      prometheusSpec = {
        replicas  = var.prometheus_replicas
        retention = var.prometheus_retention
        externalLabels = {
          cluster     = var.cluster_name
          environment = var.environment_tier
        }
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        resources = {
          requests = { cpu = local.prometheus_resources.cpu_request, memory = local.prometheus_resources.memory_request }
          limits   = { cpu = local.prometheus_resources.cpu_limit, memory = local.prometheus_resources.memory_limit }
        }
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class_name
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = var.prometheus_storage_size } }
            }
          }
        }
        nodeSelector    = { "patheya-express.io/node-role" = "system" }
        tolerations     = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
        securityContext = { runAsNonRoot = true, runAsUser = 65534, fsGroup = 65534 }
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        replicas = var.alertmanager_replicas
        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class_name
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "5Gi" } }
            }
          }
        }
        # Mounts the two ExternalSecret-synced Secrets (alertmanager-secrets.tf) into the pod at
        # /etc/alertmanager/secrets/<name>/<key> — exactly the paths alertmanager_config's
        # *_file fields above reference.
        secrets         = ["alertmanager-slack-webhook", "alertmanager-pagerduty-key"]
        nodeSelector    = { "patheya-express.io/node-role" = "system" }
        tolerations     = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
        securityContext = { runAsNonRoot = true, runAsUser = 65534, fsGroup = 65534 }
      }
      config = local.alertmanager_config
    }

    grafana = {
      replicas    = var.grafana_replicas
      persistence = { enabled = false }
      admin = {
        existingSecret = "grafana-admin-credentials"
        userKey        = "username"
        passwordKey    = "password"
      }
      serviceAccount = {
        create      = true
        name        = "kube-prometheus-stack-grafana"
        annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.grafana.arn }
      }
      sidecar = {
        dashboards = {
          enabled          = true
          label            = "grafana_dashboard"
          labelValue       = "1"
          folderAnnotation = "grafana_folder"
          provider         = { foldersFromFilesStructure = false }
        }
        datasources = {
          enabled    = true
          label      = "grafana_datasource"
          labelValue = "1"
        }
      }
      "grafana.ini" = {
        server = { root_url = "%(protocol)s://%(domain)s/" }
        users  = { default_theme = "dark" }
        # SSO-ready, deliberately disabled — this task's Section 3 asks for "SSO-ready
        # configuration," not a live IdP integration (none is chosen yet). Flip enabled=true and
        # supply client_id/client_secret/auth_url/token_url/api_url once one is.
        "auth.generic_oauth" = {
          enabled = false
          name    = "SSO"
          scopes  = "openid profile email"
        }
      }
      nodeSelector    = { "patheya-express.io/node-role" = "system" }
      tolerations     = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
      securityContext = { runAsNonRoot = true, runAsUser = 472, fsGroup = 472 }
    }

    prometheusOperator = {
      admissionWebhooks = { enabled = true, patch = { enabled = true } }
      nodeSelector      = { "patheya-express.io/node-role" = "system" }
      tolerations       = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    }

    nodeExporter     = { enabled = true }
    kubeStateMetrics = { enabled = true }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.0"
  wait       = true
  atomic     = true
  timeout    = 600 # larger chart, more CRDs/objects than any other addon this repository installs — the default 300s is too tight

  values = [yamlencode(local.kube_prometheus_stack_values)]

  depends_on = [
    kubernetes_resource_quota_v1.monitoring,
    kubernetes_manifest.grafana_admin_external_secret,
    kubernetes_manifest.alertmanager_slack_webhook_external_secret,
    kubernetes_manifest.alertmanager_pagerduty_key_external_secret,
  ]
}
