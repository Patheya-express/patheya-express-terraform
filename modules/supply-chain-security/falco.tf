# Falco — runtime syscall-level detection (a genuinely different signal from everything else in
# this module: Kyverno blocks at admission time, Trivy scans image contents; Falco watches what a
# already-running, already-admitted, already-scanned-clean container actually *does*, which is
# the layer that catches a supply-chain compromise none of the earlier layers were positioned to
# see). Default ruleset only — this task's Section 7 explicitly says "no custom application rules
# yet," which is honest: there's no running application yet for a custom rule to be tuned
# against.

locals {
  falco_values = {
    driver = {
      # modern_ebpf: no kernel module to build/sign, no host kernel-header dependency — the
      # correct default on EKS's managed AMIs (AL2023, modules/eks's amiFamily), which don't ship
      # kernel headers for the classic kernel-module driver path.
      kind = "modern_ebpf"
    }

    # Falco runs on EVERY node — the on-demand system group AND every Karpenter-provisioned node
    # (on-demand or spot), unlike every other addon in this repository, which is deliberately
    # pinned to the system node group only. A node Falco isn't running on is a node with no
    # runtime detection at all, which defeats the point.
    tolerations = [
      { operator = "Exists" }
    ]

    resources = {
      requests = { cpu = "100m", memory = "512Mi" }
      limits   = { cpu = "500m", memory = "1Gi" }
    }

    metrics = {
      enabled = true
    }

    falcosidekick = {
      enabled = true
      # Routes every Falco alert into the SAME Alertmanager Phase 5 already installed — no second
      # notification pipeline, no second Slack/PagerDuty placeholder secret to manage.
      config = {
        alertmanager = {
          hostport        = "http://${var.alertmanager_endpoint}"
          minimumpriority = "warning"
        }
      }
      webui = {
        enabled = false # an extra always-on UI this phase has no requirement for; falcosidekick's own metrics + Alertmanager routing are sufficient
      }
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }
  }
}

resource "helm_release" "falco" {
  name       = "falco"
  namespace  = kubernetes_namespace_v1.security["falco"].metadata[0].name
  repository = "https://falcosecurity.github.io/charts"
  chart      = "falco"
  version    = "4.8.1"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.falco_values)]

  depends_on = [kubernetes_resource_quota_v1.security]
}
