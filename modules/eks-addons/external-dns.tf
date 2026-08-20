data "aws_iam_policy_document" "external_dns_assume" {
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
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.name_prefix}-external-dns-role"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "external-dns-irsa-role" })
}

# Scoped to exactly this environment's own zone (var.route53_zone_id) — never every hosted zone
# in the account. Production's zone is the apex (cloud-architecture-blueprint.md Section 6);
# development/staging's is their own delegated subdomain zone (Phase 2's module.route53 per
# environment) — either way, one zone ID, passed in, never discovered/enumerated broadly.
data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"] # ListHostedZones has no per-zone ARN to scope to — required for ExternalDNS to identify var.domain_filter's zone by name in the first place, before every subsequent write narrows to it above
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "${var.name_prefix}-external-dns-policy"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.0"
  wait       = true
  atomic     = true

  set {
    name  = "provider.name"
    value = "aws"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }
  set {
    name  = "domainFilters[0]"
    value = var.domain_filter
  }
  set {
    name  = "zoneIdFilters[0]"
    value = var.route53_zone_id
  }
  set {
    name  = "policy"
    value = "sync" # ExternalDNS may also delete records it no longer sees an Ingress for — matches "declarative, Git is truth" (platform-standards.md Section 1); "upsert-only" would let stale records accumulate forever
  }
  # TXT ownership records (this task's Section 7) — required whenever `policy = sync`, so a
  # second ExternalDNS instance (or a manual record) can never be silently overwritten/deleted
  # without ExternalDNS recognizing it doesn't own that record.
  set {
    name  = "txtOwnerId"
    value = var.cluster_name
  }
  set {
    name  = "txtPrefix"
    value = "external-dns-"
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
