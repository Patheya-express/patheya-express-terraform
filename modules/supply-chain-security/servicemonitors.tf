# Trivy Operator's own chart creates its ServiceMonitor natively (trivy-operator.tf's
# serviceMonitor.enabled = true) — no duplicate object needed here. Kyverno and Falco get
# hand-written PodMonitors instead, selecting literal container port numbers (Kyverno's
# well-documented 8000 across all four controllers, Falco's 8765, falcosidekick's 2801) rather
# than relying on each chart's own serviceMonitor-enable flag, matching the same conservative
# choice modules/observability/servicemonitors.tf already made for the addons whose exact chart
# schema this repository hasn't independently verified against a live cluster.

resource "kubernetes_manifest" "podmonitor_kyverno" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "kyverno"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["kyverno"] }
      selector          = { matchLabels = { "app.kubernetes.io/instance" = "kyverno" } }
      podMetricsEndpoints = [
        { targetPort = 8000, interval = "30s", path = "/metrics" },
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "podmonitor_falco" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "falco"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["falco"] }
      selector          = { matchLabels = { "app.kubernetes.io/name" = "falco" } }
      podMetricsEndpoints = [
        { targetPort = 8765, interval = "30s", path = "/metrics" },
      ]
    }
  }

  depends_on = [helm_release.falco]
}

resource "kubernetes_manifest" "podmonitor_falcosidekick" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "falcosidekick"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["falco"] }
      selector          = { matchLabels = { "app.kubernetes.io/name" = "falcosidekick" } }
      podMetricsEndpoints = [
        { targetPort = 2801, interval = "30s", path = "/metrics" },
      ]
    }
  }

  depends_on = [helm_release.falco]
}
