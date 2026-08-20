# One repo-credential template (ArgoCD's `argocd.argoproj.io/secret-type: repo-creds` shape),
# matched by URL prefix — covers both the gitops repo and the backend repo (both under the same
# https://github.com/patheya-express/ org) without needing a separate Secret per repository.
# Synced from Secrets Manager via the SAME ClusterSecretStore Phase 4 installed — no second
# External Secrets Operator, no second store, matching the exact pattern
# modules/observability/alertmanager-secrets.tf already established for a different placeholder
# credential.
#
# Empty/unpopulated works today — both repositories are local-only, no real GitHub remote to
# authenticate against yet. Once real remotes exist, populate this per docs/argocd-guide.md;
# nothing here needs to change to activate it.

resource "kubernetes_manifest" "argocd_repo_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-repo-credentials"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-repo-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          metadata = {
            labels = {
              "argocd.argoproj.io/secret-type" = "repo-creds"
            }
          }
          data = {
            url      = "https://github.com/patheya-express/"
            username = "{{ .username }}"
            password = "{{ .password }}"
          }
        }
      }
      dataFrom = [
        {
          extract = {
            key = var.repo_credentials_secret_arn
          }
        }
      ]
    }
  }
}
