# "monitoring"/"logging"/"tracing" already exist — created empty, PSA-restricted-labeled, by
# Phase 3's modules/eks-addons/namespaces.tf specifically so Phase 5 wouldn't need to also own
# namespace lifecycle for them (see that file's own comment: "empty of workloads until Phase 5
# actually installs something into them"). This module does NOT create a second
# kubernetes_namespace_v1 for any of the three — doing so would collide with the already-applied
# Namespace objects Phase 3 owns. It only adds the ResourceQuota/LimitRange those namespaces
# didn't need while empty but do now that they host real Prometheus/Loki/Tempo workloads —
# exactly the same "quota follows the first real workload" precedent Phase 4 set for
# data-platform.
#
# "observability" is the one genuinely new namespace this phase creates, for the OpenTelemetry
# Collector — a cross-cutting component that doesn't belong to Prometheus, Loki, or Tempo
# specifically.

locals {
  # environment_tier drives resource ceilings the same way modules/eks-addons's namespaces.tf
  # already does for patheya-backend/patheya-frontend.
  is_production = var.environment_tier == "production"

  observability_quota = {
    "requests.cpu"    = local.is_production ? "8" : "4"
    "requests.memory" = local.is_production ? "16Gi" : "8Gi"
    "limits.cpu"      = local.is_production ? "16" : "8"
    "limits.memory"   = local.is_production ? "32Gi" : "16Gi"
    "pods"            = "20"
  }

  monitoring_quota = {
    "requests.cpu"    = local.is_production ? "8" : "4"
    "requests.memory" = local.is_production ? "16Gi" : "8Gi"
    "limits.cpu"      = local.is_production ? "16" : "8"
    "limits.memory"   = local.is_production ? "32Gi" : "16Gi"
    "pods"            = "20"
  }

  logging_quota = {
    "requests.cpu"    = local.is_production ? "6" : "3"
    "requests.memory" = local.is_production ? "12Gi" : "6Gi"
    "limits.cpu"      = local.is_production ? "12" : "6"
    "limits.memory"   = local.is_production ? "24Gi" : "12Gi"
    "pods"            = "30" # Promtail is a DaemonSet — one pod per node, so this ceiling needs headroom beyond the "workload" namespaces' 20
  }

  tracing_quota = {
    "requests.cpu"    = local.is_production ? "4" : "2"
    "requests.memory" = local.is_production ? "8Gi" : "4Gi"
    "limits.cpu"      = local.is_production ? "8" : "4"
    "limits.memory"   = local.is_production ? "16Gi" : "8Gi"
    "pods"            = "10"
  }
}

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
    labels = {
      "app.kubernetes.io/part-of"          = "patheya-express"
      "app.kubernetes.io/managed-by"       = "terraform"
      "patheya-express.io/component"       = "observability"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "observability" {
  metadata {
    name      = "observability-quota"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    hard = local.observability_quota
  }
}

resource "kubernetes_limit_range_v1" "observability" {
  metadata {
    name      = "observability-limits"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "250m", memory = "256Mi" }
      default_request = { cpu = "100m", memory = "128Mi" }
    }
  }
}

resource "kubernetes_resource_quota_v1" "monitoring" {
  metadata {
    name      = "monitoring-quota"
    namespace = "monitoring"
  }
  spec {
    hard = local.monitoring_quota
  }
}

resource "kubernetes_limit_range_v1" "monitoring" {
  metadata {
    name      = "monitoring-limits"
    namespace = "monitoring"
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "500m", memory = "1Gi" }
      default_request = { cpu = "100m", memory = "256Mi" }
    }
  }
}

resource "kubernetes_resource_quota_v1" "logging" {
  metadata {
    name      = "logging-quota"
    namespace = "logging"
  }
  spec {
    hard = local.logging_quota
  }
}

resource "kubernetes_limit_range_v1" "logging" {
  metadata {
    name      = "logging-limits"
    namespace = "logging"
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "250m", memory = "512Mi" }
      default_request = { cpu = "50m", memory = "128Mi" }
    }
  }
}

resource "kubernetes_resource_quota_v1" "tracing" {
  metadata {
    name      = "tracing-quota"
    namespace = "tracing"
  }
  spec {
    hard = local.tracing_quota
  }
}

resource "kubernetes_limit_range_v1" "tracing" {
  metadata {
    name      = "tracing-limits"
    namespace = "tracing"
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "250m", memory = "512Mi" }
      default_request = { cpu = "50m", memory = "128Mi" }
    }
  }
}
