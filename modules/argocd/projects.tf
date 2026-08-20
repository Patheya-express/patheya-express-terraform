# One AppProject per layer — this is the actual mechanism that keeps "avoid circular
# dependencies" true even if a manifest in the gitops repo is ever wrong or compromised:
# each layer's Applications can only source from the repos, and can only deploy into the
# namespaces, this AppProject allows. The applications layer specifically can never target
# kube-system/argocd/monitoring/etc even if someone tried — not just "wouldn't," but "the API
# server rejects it."

resource "kubernetes_manifest" "appproject_bootstrap" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "bootstrap"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      description = "The root Application only — seeds the platform layer. Nothing else is ever added here."
      sourceRepos = [var.gitops_repo_url]
      destinations = [
        { namespace = kubernetes_namespace_v1.argocd.metadata[0].name, server = "https://kubernetes.default.svc" }
      ]
      clusterResourceWhitelist = [
        { group = "argoproj.io", kind = "AppProject" },
        { group = "argoproj.io", kind = "Application" },
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "appproject_platform" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      description = "Cluster-wide policy/GitOps tooling that Terraform deliberately does not own (future Kyverno). Does NOT include the Terraform-managed addons (Karpenter, NGINX, cert-manager, ESO, the Prometheus stack, Loki, Tempo) — see docs/argocd-guide.md's ownership-boundary section for why those stay Terraform-owned."
      sourceRepos = [var.gitops_repo_url]
      destinations = [
        { namespace = kubernetes_namespace_v1.argocd.metadata[0].name, server = "https://kubernetes.default.svc" }
      ]
      clusterResourceWhitelist = [
        { group = "argoproj.io", kind = "Application" },
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "appproject_infrastructure" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "infrastructure"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      description = "PriorityClass + NetworkPolicy for the application namespaces Terraform already created (patheya-backend/patheya-frontend) — deliberately excludes Namespace/ResourceQuota/LimitRange, which stay Terraform-owned (modules/eks-addons/namespaces.tf)."
      sourceRepos = [var.gitops_repo_url]
      destinations = [
        { namespace = "patheya-backend", server = "https://kubernetes.default.svc" },
        { namespace = "patheya-frontend", server = "https://kubernetes.default.svc" },
      ]
      clusterResourceWhitelist = [
        { group = "argoproj.io", kind = "Application" },
        { group = "scheduling.k8s.io", kind = "PriorityClass" },
      ]
      namespaceResourceWhitelist = [
        { group = "networking.k8s.io", kind = "NetworkPolicy" },
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "appproject_applications" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "applications"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      description = "api-gateway/workers/frontend Deployments. Manual sync only (this phase's explicit scope — see docs/gitops-bootstrap-guide.md) and, in production, gated by a sync window requiring deliberate approval even for a manual sync (cloud-architecture-blueprint.md Section 9)."
      sourceRepos = [var.gitops_repo_url, var.backend_repo_url]
      destinations = [
        { namespace = "patheya-backend", server = "https://kubernetes.default.svc" },
        { namespace = "patheya-frontend", server = "https://kubernetes.default.svc" },
      ]
      clusterResourceWhitelist = []
      namespaceResourceWhitelist = [
        { group = "apps", kind = "Deployment" },
        { group = "", kind = "Service" },
        { group = "", kind = "ServiceAccount" },
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Secret" },
        { group = "autoscaling", kind = "HorizontalPodAutoscaler" },
        { group = "policy", kind = "PodDisruptionBudget" },
        { group = "networking.k8s.io", kind = "Ingress" },
      ]
      # kubernetes_manifest's "manifest" attribute is a plain HCL map, not a typed resource
      # schema — a `dynamic` block (which only applies to real nested blocks) can't be used here.
      # A production-only list entry, built with a plain conditional, is the correct equivalent:
      # every sync in this AppProject is manual-only already (no Application here sets
      # syncPolicy.automated), and in production a deny window additionally blocks even a manual
      # sync outside the stated review hours — belt-and-suspenders on top of "manual sync is
      # already required everywhere," not a replacement for it.
      syncWindows = var.environment_tier == "production" ? [
        {
          kind         = "deny"
          schedule     = "0 0-8,20-23 * * *" # 00:00-08:00 and 20:00-23:59 UTC — outside typical platform-engineering working hours (05:30-13:30 UTC / 11:00-19:00 IST)
          duration     = "1h"
          applications = ["*"]
          manualSync   = false
        }
      ] : []
    }
  }

  depends_on = [helm_release.argocd]
}
