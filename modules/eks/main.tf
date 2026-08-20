resource "aws_cloudwatch_log_group" "cluster" {
  # EKS creates this automatically on first log delivery if it doesn't already exist, but with no
  # retention/encryption configuration — creating it explicitly first means the very first log
  # line is already retention-bounded and KMS-encrypted, not delivered briefly-unmanaged before a
  # later Terraform run catches up.
  name              = "/aws/eks/${var.name_prefix}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "eks", Purpose = "control-plane-log-group" })
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = merge(var.tags, { Application = "eks", Purpose = "eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.name_prefix
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_app_subnet_ids
    security_group_ids      = [var.eks_node_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  # Every log type, every environment — platform-standards.md Section 13 (security) doesn't carve
  # out an exception for control-plane audit logging by environment tier the way it does for
  # application log retention.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  # EKS Access Entries (access-entries.tf) are this cluster's only authorization mechanism — the
  # legacy aws-auth ConfigMap path is never enabled.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false # explicit access entries only (access-entries.tf) — not even the Terraform-run identity gets an implicit grant
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster_policy,
  ]

  tags = merge(var.tags, { Application = "eks", Purpose = "eks-cluster" })
}

# OIDC provider for IRSA — thumbprint fetched live from the cluster's own issuer, same pattern
# (and same typo-avoidance reasoning) as modules/iam's GitHub OIDC provider in Phase 2.
data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    data.tls_certificate.cluster_oidc.certificates[length(data.tls_certificate.cluster_oidc.certificates) - 1].sha1_fingerprint,
  ]

  tags = merge(var.tags, { Application = "eks", Purpose = "eks-oidc-provider" })
}
