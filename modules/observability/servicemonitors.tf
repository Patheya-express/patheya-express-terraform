# Application Monitoring Foundation (this task's Section 9) for everything already installed by
# Phase 3/4 — every one of these components already exposes a /metrics endpoint (several
# explicitly left "nothing scrapes it yet" in their own Phase 3/4 comments); this file is what
# finally scrapes them. No changes to any Phase 3/4 chart's own values were needed — every
# selector below targets a Service/Pod label those charts already create by default.
#
# ServiceMonitor where a stable, well-known Service+port name exists (NGINX, PgBouncer — both
# ours, both already confirmed named "metrics"). PodMonitor (selecting a literal container port
# number instead of a Service port name) everywhere else, to avoid depending on an assumed
# Service port name this repository doesn't itself define.

resource "kubernetes_manifest" "servicemonitor_nginx_ingress" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "nginx-ingress"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["ingress-nginx"] }
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "ingress-nginx"
          "app.kubernetes.io/component" = "controller"
        }
      }
      endpoints = [{ port = "metrics", interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "servicemonitor_pgbouncer" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "pgbouncer"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["data-platform"] }
      selector = {
        matchLabels = { "app.kubernetes.io/name" = "pgbouncer" }
      }
      endpoints = [{ port = "metrics", interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "podmonitor_karpenter" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "karpenter"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector   = { matchNames = ["kube-system"] }
      selector            = { matchLabels = { "app.kubernetes.io/name" = "karpenter" } }
      podMetricsEndpoints = [{ port = "http-metrics", interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "podmonitor_aws_lb_controller" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "aws-load-balancer-controller"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector = { matchNames = ["kube-system"] }
      selector          = { matchLabels = { "app.kubernetes.io/name" = "aws-load-balancer-controller" } }
      # targetPort (a literal number), not port (a named port) — this repository's own
      # aws-lb-controller.tf never names its metrics container port, so only the number (the
      # chart's well-documented default) is a safe selector here.
      podMetricsEndpoints = [{ targetPort = 8080, interval = "30s", path = "/metrics" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "podmonitor_external_dns" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "external-dns"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector   = { matchNames = ["kube-system"] }
      selector            = { matchLabels = { "app.kubernetes.io/name" = "external-dns" } }
      podMetricsEndpoints = [{ port = "http", interval = "30s", path = "/metrics" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "podmonitor_cert_manager" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "cert-manager"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector   = { matchNames = ["cert-manager"] }
      selector            = { matchLabels = { "app.kubernetes.io/name" = "cert-manager" } }
      podMetricsEndpoints = [{ targetPort = 9402, interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_manifest" "podmonitor_external_secrets" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "external-secrets"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      namespaceSelector   = { matchNames = ["external-secrets"] }
      selector            = { matchLabels = { "app.kubernetes.io/name" = "external-secrets" } }
      podMetricsEndpoints = [{ targetPort = 8080, interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
