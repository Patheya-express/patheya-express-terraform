# The ONE object Terraform creates that hands control to Git — everything else in the
# bootstrap -> platform -> infrastructure -> applications chain is defined in the gitops
# repository from this point on, not in Terraform. Re-running `terraform apply` on this module
# never needs to change once this object exists; the gitops repo's own commits are what evolve
# the platform after bootstrap.
#
# The source path is environment-specific ("bootstrap/<environment_tier>") because each
# environment is its own EKS cluster with its own separate ArgoCD installation (the blueprint's
# one-cluster-per-environment model, unchanged since Phase 3) — this development cluster's
# ArgoCD must never sync production's overlay path, and there is no single shared "bootstrap"
# path that would be correct for all three without risking exactly that.

resource "kubernetes_manifest" "root_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      # Prevents accidental deletion of the root Application from cascading into deleting every
      # child Application (and everything they in turn manage) — the one place in this whole tree
      # where "someone fat-fingered a delete" should NOT be catastrophic by default.
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "bootstrap"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "HEAD"
        path           = "bootstrap/${var.environment_tier}"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false"] # every namespace this tree ever touches (argocd, patheya-backend, patheya-frontend) already exists, Terraform-created — no layer in this tree should ever create one itself
      }
    }
  }

  depends_on = [
    kubernetes_manifest.appproject_bootstrap,
    kubernetes_manifest.appproject_platform,
    kubernetes_manifest.appproject_infrastructure,
    kubernetes_manifest.appproject_applications,
  ]
}
