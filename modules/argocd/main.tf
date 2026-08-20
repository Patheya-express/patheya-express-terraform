# ArgoCD's own Helm release — installed and upgraded by Terraform exactly like every other addon
# in this repository (Karpenter, NGINX, cert-manager, kube-prometheus-stack, Loki, Tempo): bump
# the pinned chart version below, re-apply. This is a deliberate choice, not a missed
# opportunity for "self-management" — see docs/argocd-guide.md's ownership-boundary section for
# why ArgoCD does NOT manage its own Helm release via a self-referential Application. Everything
# ArgoCD deploys *other than itself* (projects.tf's AppProjects, root-application.tf's root
# Application, and everything the gitops repository defines beneath it) is what "the platform can
# eventually manage itself" refers to.

locals {
  is_production = var.environment_tier == "production"

  argocd_replicas = {
    controller      = local.is_production ? 1 : 1 # the application controller is not horizontally scaled by replica count in this chart version — sharding (a separate concern) is not configured at this phase's scale
    server          = local.is_production ? 2 : 1
    repo_server     = local.is_production ? 2 : 1
    application_set = 1
  }

  # RBAC (platform-standards.md Section 7) — platform-engineering gets admin, everyone else
  # read-only by default. Group-based mapping only added once var.admin_rbac_group is non-null
  # (IAM Identity Center actually enabled) — no fabricated group name against an Identity Center
  # instance that may not exist yet, same gating pattern Phase 2/3 already use for access
  # entries.
  rbac_policy_lines = concat(
    ["p, role:readonly, applications, get, */*, allow",
    "p, role:readonly, projects, get, *, allow"],
    var.admin_rbac_group != null ? ["g, ${var.admin_rbac_group}, role:admin"] : []
  )

  argocd_values = {
    fullnameOverride = "argocd"

    global = {
      nodeSelector = { "patheya-express.io/node-role" = "system" }
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    }

    configs = {
      cm = {
        "admin.enabled"                      = "true" # local admin retained for initial bootstrap access — see docs/argocd-guide.md for the plan to disable it once SSO (Grafana's same deferred-SSO posture) is live
        "timeout.reconciliation"             = "180s"
        "application.resourceTrackingMethod" = "annotation"

        # Kyverno's engine itself is Terraform-owned (modules/supply-chain-security), never
        # synced by ArgoCD — but PolicyException grants (docs/exception-process.md's documented
        # workflow) are the one Kyverno object type meant to live in the gitops repo, reviewed
        # like any other change there. ArgoCD has no built-in understanding of either CRD's
        # status, so without this it would report both as permanently "Unknown" rather than
        # "Healthy" the moment either is ever added to an Application.
        "resource.customizations.health.kyverno.io_ClusterPolicy"   = <<-LUA
          hs = {}
          hs.status = "Healthy"
          hs.message = "ClusterPolicy is a config object with no reconciliation status ArgoCD needs to wait on."
          return hs
        LUA
        "resource.customizations.health.kyverno.io_PolicyException" = <<-LUA
          hs = {}
          hs.status = "Healthy"
          hs.message = "PolicyException is a config object with no reconciliation status ArgoCD needs to wait on."
          return hs
        LUA
      }
      params = {
        "server.insecure" = "true" # plain HTTP inside the cluster — no Ingress in this phase (same posture as Grafana: reach it via kubectl port-forward), TLS termination deferred until this is actually exposed externally
      }
      rbac = {
        "policy.default" = "role:readonly"
        "policy.csv"     = join("\n", local.rbac_policy_lines)
      }
      secret = {
        createSecret = false # this module's own secrets.tf ExternalSecret owns the repo-credentials Secret; the chart's own createSecret default would create an unrelated (and here, unwanted) placeholder
      }
    }

    controller = {
      replicas = local.argocd_replicas.controller
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
    }

    server = {
      replicas = local.argocd_replicas.server
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    repoServer = {
      replicas = local.argocd_replicas.repo_server
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    applicationSet = {
      replicas = local.argocd_replicas.application_set
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }

    redis = {
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }

    # Redis HA (a separate Redis Sentinel cluster) is the chart's production-scale option —
    # deliberately not enabled at this phase's scale: ArgoCD's Redis is a reconciliation cache,
    # not a source of truth (Git is), so a brief cache-rebuild after a single Redis pod restart
    # is a non-event, not an availability incident.
    "redis-ha" = {
      enabled = false
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.11"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.argocd_values)]

  depends_on = [
    kubernetes_resource_quota_v1.argocd,
    kubernetes_manifest.argocd_repo_credentials_external_secret,
  ]
}
