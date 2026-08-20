# Application namespaces (patheya-backend/patheya-frontend — cloud-architecture-blueprint.md
# Section 3, environment-agnostic names since environment is now the cluster itself, not a
# namespace suffix) plus the three observability-prep namespaces this task's Section 13 asks for
# (monitoring/logging/tracing — empty of workloads until Phase 5 installs anything into them).
#
# No application workload, ServiceAccount-for-a-controller-that-doesn't-exist-yet, or ArgoCD RBAC
# binding is created here — this task's Section 14 (GitOps readiness) and Section 13
# (observability foundation) both explicitly scope this phase to *namespace and policy*
# preparation only. A RoleBinding pointing at a ServiceAccount no controller has created yet is
# exactly the kind of placeholder this task explicitly forbids.

locals {
  application_namespaces = {
    patheya-backend = {
      component = "backend"
    }
    patheya-frontend = {
      component = "frontend"
    }
  }

  platform_prep_namespaces = {
    monitoring = { component = "observability" }
    logging    = { component = "observability" }
    tracing    = { component = "observability" }
  }

  # Unlike platform_prep_namespaces above, this one hosts a real, running workload as of this
  # phase (PgBouncer — pgbouncer.tf) — it gets its own ResourceQuota/LimitRange like the
  # application namespaces do, not the bare, workload-free treatment monitoring/logging/tracing
  # get until Phase 5 actually installs something into them.
  data_platform_namespaces = {
    data-platform = { component = "data-platform" }
  }
}

resource "kubernetes_namespace_v1" "application" {
  for_each = local.application_namespaces

  metadata {
    name = each.key
    # Deliberately NOT merging var.tags (AWS tag values) into Kubernetes labels here — AWS tag
    # values permit characters and lengths (spaces, colons, >63 chars) that Kubernetes label
    # values reject outright, so a generic merge would intermittently fail apply depending on
    # what a given tag's value happened to contain. Static, known-safe labels only.
    labels = {
      "app.kubernetes.io/part-of"    = "patheya-express"
      "app.kubernetes.io/managed-by" = "terraform"
      "patheya-express.io/component" = each.value.component
      # Pod Security Admission — restricted profile (platform-standards.md Section 7) —
      # enforced by the API server itself at admission time, not just documented intent.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "application" {
  for_each = local.application_namespaces

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace_v1.application[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.environment_tier == "production" ? "16" : "8"
      "requests.memory" = var.environment_tier == "production" ? "32Gi" : "16Gi"
      "limits.cpu"      = var.environment_tier == "production" ? "32" : "16"
      "limits.memory"   = var.environment_tier == "production" ? "64Gi" : "32Gi"
      "pods"            = "50"
    }
  }
}

resource "kubernetes_limit_range_v1" "application" {
  for_each = local.application_namespaces

  metadata {
    name      = "${each.key}-limits"
    namespace = kubernetes_namespace_v1.application[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

resource "kubernetes_namespace_v1" "platform_prep" {
  for_each = local.platform_prep_namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of"          = "patheya-express"
      "app.kubernetes.io/managed-by"       = "terraform"
      "patheya-express.io/component"       = each.value.component
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "kubernetes_namespace_v1" "data_platform" {
  for_each = local.data_platform_namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of"          = "patheya-express"
      "app.kubernetes.io/managed-by"       = "terraform"
      "patheya-express.io/component"       = each.value.component
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "data_platform" {
  for_each = local.data_platform_namespaces

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace_v1.data_platform[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.environment_tier == "production" ? "4" : "2"
      "requests.memory" = var.environment_tier == "production" ? "8Gi" : "4Gi"
      "limits.cpu"      = var.environment_tier == "production" ? "8" : "4"
      "limits.memory"   = var.environment_tier == "production" ? "16Gi" : "8Gi"
      "pods"            = "20"
    }
  }
}

resource "kubernetes_limit_range_v1" "data_platform" {
  for_each = local.data_platform_namespaces

  metadata {
    name      = "${each.key}-limits"
    namespace = kubernetes_namespace_v1.data_platform[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "250m"
        memory = "256Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}
