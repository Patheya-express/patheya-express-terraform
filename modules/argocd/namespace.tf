resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/part-of"          = "patheya-express"
      "app.kubernetes.io/managed-by"       = "terraform"
      "patheya-express.io/component"       = "gitops"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "argocd" {
  metadata {
    name      = "argocd-quota"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
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

resource "kubernetes_limit_range_v1" "argocd" {
  metadata {
    name      = "argocd-limits"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "500m", memory = "512Mi" }
      default_request = { cpu = "100m", memory = "128Mi" }
    }
  }
}
