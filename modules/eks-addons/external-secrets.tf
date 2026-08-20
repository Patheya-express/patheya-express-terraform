# External Secrets Operator (this task's Section 6) — resolves the "production secrets are
# still Kustomize placeholders" gap the blueprint's baseline (Phase 1A audit) and Section 11
# both flag: real, rotatable, audited secret material synced from Secrets Manager into
# Kubernetes Secret objects shaped exactly like Phase 1A's secretGenerator output, never a
# plaintext value committed to Git.

data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name_prefix}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "external-secrets-irsa-role" })
}

# Two resource shapes: this environment's own path-prefixed secrets (modules/secrets-manager's
# naming) plus the Aurora master secret's exact ARN — RDS-managed secrets get an
# AWS-auto-generated name ("rds!cluster-<uuid>") that doesn't follow our patheya-express/<env>/
# naming scheme, so it can't be reached by the prefix wildcard alone and is granted explicitly
# instead (still least-privilege: one named resource, not "every RDS secret in the account").
data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_manager_path_prefix}/*",
      var.aurora_master_secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "${var.name_prefix}-external-secrets-policy"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.5"
  wait             = true
  atomic           = true

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets.arn
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
}

resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

# --- Synchronized secrets (Section 6's "Secret synchronization") ---
#
# Both ExternalSecrets below produce a real Kubernetes Secret that no Deployment in this phase
# reads yet — the same "prepared, not populated" posture Phase 3 used for the observability
# namespaces (docs/eks-platform-guide.md). PgBouncer (pgbouncer.tf) is the one exception: it
# does read pgbouncer-credentials, because PgBouncer itself is infrastructure this phase
# explicitly deploys, not an application workload.

resource "kubernetes_manifest" "pgbouncer_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "pgbouncer-credentials"
      namespace = kubernetes_namespace_v1.data_platform["data-platform"].metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "pgbouncer-credentials"
        creationPolicy = "Owner"
      }
      dataFrom = [
        {
          extract = {
            key = var.aurora_master_secret_arn
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.cluster_secret_store]
}

resource "kubernetes_manifest" "backend_database_url_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "backend-database-url"
      namespace = kubernetes_namespace_v1.application["patheya-backend"].metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "backend-database-url"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            # Points at PgBouncer's in-cluster Service (pgbouncer.tf), never at Aurora directly —
            # platform-standards.md Section 16: "no application code connects directly to the
            # Aurora writer/reader endpoints." sslmode=require enforces TLS client-side, matching
            # the server-side rds.force_ssl=1 parameter (modules/aurora/main.tf).
            DATABASE_URL = "postgresql://{{ .username }}:{{ .password }}@pgbouncer.data-platform.svc.cluster.local:6432/${var.aurora_database_name}?sslmode=require"
          }
        }
      }
      dataFrom = [
        {
          extract = {
            key = var.aurora_master_secret_arn
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.cluster_secret_store, kubernetes_namespace_v1.application]
}

# Phase 9 (Enterprise Workload Deployment) — the fourth and last piece of "no Deployment reads
# these yet" this file's own header comment flagged as not-yet-true: jwt-signing-key/cloudinary/
# razorpay/smtp were the four human-populated secrets data/main.tf's module.secrets_manager
# creates as empty containers (docs/secrets-guide.md), with no ExternalSecret syncing any of them
# into the cluster until now. One target Secret, not four — fewer envFrom entries for the
# Deployment, and the four source secrets already logically belong together (every one of them is
# "third-party/external credential material," the exact category docs/secrets-guide.md's
# `external_credential_secrets` name describes).
#
# Expected JSON shape of each source secret (docs/secrets-guide.md documents this contract for
# whoever runs `aws secretsmanager put-secret-value`):
#   jwt-signing-key: {"accessSecret": "...", "refreshSecret": "..."}
#   cloudinary:      {"cloudName": "...", "apiKey": "...", "apiSecret": "..."}
#   razorpay:        {"keyId": "...", "keySecret": "..."}
#   smtp:            {"host": "...", "port": "...", "user": "...", "pass": "...", "from": "..."}
resource "kubernetes_manifest" "backend_app_secrets_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "backend-app-secrets"
      namespace = kubernetes_namespace_v1.application["patheya-backend"].metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "backend-app-secrets"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            JWT_ACCESS_SECRET     = "{{ .accessSecret }}"
            JWT_REFRESH_SECRET    = "{{ .refreshSecret }}"
            CLOUDINARY_CLOUD_NAME = "{{ .cloudName }}"
            CLOUDINARY_API_KEY    = "{{ .apiKey }}"
            CLOUDINARY_API_SECRET = "{{ .apiSecret }}"
            RAZORPAY_KEY_ID       = "{{ .keyId }}"
            RAZORPAY_KEY_SECRET   = "{{ .keySecret }}"
            SMTP_HOST             = "{{ .host }}"
            SMTP_PORT             = "{{ .port }}"
            SMTP_USER             = "{{ .user }}"
            SMTP_PASS             = "{{ .pass }}"
            SMTP_FROM             = "{{ .from }}"
          }
        }
      }
      dataFrom = [
        { extract = { key = var.app_secrets_arns["jwt-signing-key"] } },
        { extract = { key = var.app_secrets_arns["cloudinary"] } },
        { extract = { key = var.app_secrets_arns["razorpay"] } },
        { extract = { key = var.app_secrets_arns["smtp"] } },
      ]
    }
  }

  depends_on = [kubernetes_manifest.cluster_secret_store, kubernetes_namespace_v1.application]
}

resource "kubernetes_manifest" "backend_redis_credentials_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "backend-redis-credentials"
      namespace = kubernetes_namespace_v1.application["patheya-backend"].metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "backend-redis-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            REDIS_HOST       = var.redis_configuration_endpoint != null ? var.redis_configuration_endpoint : var.redis_primary_endpoint
            REDIS_PORT       = tostring(var.redis_port)
            REDIS_AUTH_TOKEN = "{{ .authToken }}"
            REDIS_TLS        = "true"
          }
        }
      }
      data = [
        {
          secretKey = "authToken"
          remoteRef = {
            key = var.redis_auth_token_secret_arn
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.cluster_secret_store, kubernetes_namespace_v1.application]
}
