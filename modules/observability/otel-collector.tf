# OpenTelemetry Collector — deployed in "deployment" mode (a central gateway, not a per-node
# DaemonSet; Promtail already owns node-level log collection) in the new "observability"
# namespace. This is the OTLP endpoint the backend's future NestJS OpenTelemetry SDK integration
# (cloud-architecture-blueprint.md Section 10, an application-code change explicitly out of this
# infrastructure-only phase's scope) sends traces/metrics/logs to — the Collector exists and is
# reachable now; nothing sends it real application telemetry until that app-code change lands.

locals {
  otel_replicas = local.is_production ? 2 : 1

  otel_collector_values = {
    fullnameOverride = "otel-collector"
    mode             = "deployment"
    replicaCount     = local.otel_replicas

    serviceAccount = {
      create = true
      name   = "otel-collector"
    }

    # k8sattributes needs read access to Pods/Namespaces/ReplicaSets across the cluster to enrich
    # incoming spans/metrics with pod/namespace/deployment metadata — a ClusterRole, not an IAM
    # role (this Collector calls no AWS API of its own; Tempo/Loki/Prometheus, which it forwards
    # to, are the ones with IRSA roles).
    clusterRole = {
      create = true
      rules = [
        {
          apiGroups = [""]
          resources = ["pods", "namespaces"]
          verbs     = ["get", "list", "watch"]
        },
        {
          apiGroups = ["apps"]
          resources = ["replicasets"]
          verbs     = ["get", "list", "watch"]
        },
      ]
    }

    config = {
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }

      processors = {
        batch = {}
        memory_limiter = {
          check_interval         = "1s"
          limit_percentage       = 80
          spike_limit_percentage = 25
        }
        k8sattributes = {
          extract = {
            metadata = ["k8s.namespace.name", "k8s.pod.name", "k8s.deployment.name", "k8s.node.name"]
          }
        }
        resource = {
          attributes = [
            { key = "cluster", value = var.cluster_name, action = "insert" },
            { key = "environment", value = var.environment_tier, action = "insert" },
          ]
        }
        probabilistic_sampler = {
          sampling_percentage = var.otel_sampling_ratio * 100
        }
      }

      exporters = {
        "otlp/tempo" = {
          endpoint = "tempo.tracing.svc.cluster.local:4317"
          tls      = { insecure = true } # in-cluster hop, same trust boundary as every other in-cluster Service-to-Service call in this platform (NGINX<->NLB is the one hop that gets real TLS, per Phase 3's ingress-guide.md)
        }
        prometheusremotewrite = {
          endpoint = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write"
        }
        loki = {
          endpoint = "http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push"
        }
      }

      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "probabilistic_sampler", "batch"]
            exporters  = ["otlp/tempo"]
          }
          metrics = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["prometheusremotewrite"]
          }
          logs = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["loki"]
          }
        }
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }

    ports = {
      otlp      = { enabled = true, containerPort = 4317, servicePort = 4317, protocol = "TCP" }
      otlp-http = { enabled = true, containerPort = 4318, servicePort = 4318, protocol = "TCP" }
    }

    nodeSelector = { "patheya-express.io/node-role" = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
  }
}

resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.108.0"
  wait       = true
  atomic     = true

  values = [yamlencode(local.otel_collector_values)]

  depends_on = [helm_release.tempo, helm_release.loki, helm_release.kube_prometheus_stack]
}
