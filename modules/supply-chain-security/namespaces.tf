locals {
  is_production = var.environment_tier == "production"

  # Falco's whole purpose — eBPF/kernel-module syscall introspection, host /proc and /dev access
  # — is fundamentally incompatible with Pod Security "restricted" (no host access, no added
  # capabilities, no privilege escalation, all of which Falco's driver needs). "privileged" is
  # the correct, honest label for it — labeling it "restricted" wouldn't make Falco a smaller
  # security surface, it would just make the label a lie the moment Falco's pod tries to start
  # and gets rejected. Kyverno and Trivy Operator are ordinary application pods with no host
  # access need, so "restricted" holds for them exactly like every other platform namespace.
  security_namespaces = {
    kyverno      = { component = "policy-enforcement", pod_security = "restricted" }
    trivy-system = { component = "vulnerability-scanning", pod_security = "restricted" }
    falco        = { component = "runtime-security", pod_security = "privileged" }
  }
}

resource "kubernetes_namespace_v1" "security" {
  for_each = local.security_namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of"          = "patheya-express"
      "app.kubernetes.io/managed-by"       = "terraform"
      "patheya-express.io/component"       = each.value.component
      "pod-security.kubernetes.io/enforce" = each.value.pod_security
      "pod-security.kubernetes.io/audit"   = each.value.pod_security
      "pod-security.kubernetes.io/warn"    = each.value.pod_security
    }
  }
}

resource "kubernetes_resource_quota_v1" "security" {
  for_each = local.security_namespaces

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace_v1.security[each.key].metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = local.is_production ? "4" : "2"
      "requests.memory" = local.is_production ? "8Gi" : "4Gi"
      "limits.cpu"      = local.is_production ? "8" : "4"
      "limits.memory"   = local.is_production ? "16Gi" : "8Gi"
      "pods"            = "30" # falco is a DaemonSet — one pod per node, needs headroom beyond a typical workload namespace's ceiling
    }
  }
}

resource "kubernetes_limit_range_v1" "security" {
  for_each = local.security_namespaces

  metadata {
    name      = "${each.key}-limits"
    namespace = kubernetes_namespace_v1.security[each.key].metadata[0].name
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = "250m", memory = "256Mi" }
      default_request = { cpu = "100m", memory = "128Mi" }
    }
  }
}
