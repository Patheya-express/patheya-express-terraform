# Syncs the two placeholder Secrets Manager containers (created by the platform/main.tf-level
# modules/secrets-manager call, ARNs passed in as variables) into the two Kubernetes Secrets
# prometheus-stack.tf's alertmanager.alertmanagerSpec.secrets list mounts into the Alertmanager
# pod. Uses the same ClusterSecretStore Phase 4 already installed — see secrets.tf's own comment
# for why this module never installs a second External Secrets Operator or SecretStore.

resource "kubernetes_manifest" "alertmanager_slack_webhook_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-slack-webhook"
      namespace = "monitoring"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "alertmanager-slack-webhook"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "webhook-url"
          remoteRef = {
            key      = var.alertmanager_slack_webhook_secret_arn
            property = "webhook-url"
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "alertmanager_pagerduty_key_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-pagerduty-key"
      namespace = "monitoring"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "alertmanager-pagerduty-key"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "key"
          remoteRef = {
            key      = var.alertmanager_pagerduty_key_secret_arn
            property = "key"
          }
        }
      ]
    }
  }
}
