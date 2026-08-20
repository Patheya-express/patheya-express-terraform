# cert-manager — DNS-01 (Route53) validated certificates for anything the environment's own zone
# covers, issued by Let's Encrypt. ACM (module.route53, Phase 2) already covers the NLB's own
# listener certificate (nginx-ingress.tf's aws-load-balancer-ssl-cert) — cert-manager exists for
# in-cluster TLS needs beyond that single NLB listener (e.g. future mTLS between services), per
# cloud-architecture-blueprint.md Section 3's own framing of cert-manager's role.

data "aws_iam_policy_document" "cert_manager_assume" {
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
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.name_prefix}-cert-manager-role"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume.json

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "cert-manager-irsa-role" })
}

data "aws_iam_policy_document" "cert_manager" {
  statement {
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager" {
  name   = "${var.name_prefix}-cert-manager-policy"
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.cert_manager.json
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.16.2"
  wait             = true
  atomic           = true

  set {
    name  = "crds.enabled"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cert_manager.arn
  }
  set {
    name  = "replicaCount"
    value = var.environment_tier == "production" ? 2 : 1
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

resource "kubernetes_manifest" "cluster_issuer_letsencrypt" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-dns01"
    }
    spec = {
      acme = {
        server = var.environment_tier == "production" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = "platform-engineering@patheyaexpress.com"
        privateKeySecretRef = {
          name = "letsencrypt-dns01-account-key"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region       = data.aws_region.current.name
                hostedZoneID = var.route53_zone_id
                role         = aws_iam_role.cert_manager.arn
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}
