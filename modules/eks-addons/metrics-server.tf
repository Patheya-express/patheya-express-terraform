# No AWS API access needed — Metrics Server only reads kubelet's own resource-metrics endpoint,
# so no IRSA role, just the Helm release. This is what the backend's already-defined HPAs
# (k8s/base/api-gateway/hpa.yaml, k8s/base/workers/hpa.yaml) need to actually function once
# deployed — an HPA with no Metrics Server backing it just never scales, silently.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = "3.12.2"
  wait       = true
  atomic     = true

  set {
    name  = "replicas"
    value = var.environment_tier == "production" ? 2 : 1
  }
  set {
    name  = "nodeSelector.patheya-express\\.io/node-role"
    value = "system"
  }
  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "podDisruptionBudget.enabled"
    value = "true"
  }
  set {
    name  = "podDisruptionBudget.minAvailable"
    value = "1"
  }
}
