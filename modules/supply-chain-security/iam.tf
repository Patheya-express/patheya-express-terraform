# Kyverno's admission/background controllers and Trivy Operator both need to pull image
# manifests (and, for Kyverno's verifyImages rule, signature/attestation OCI artifacts) from
# ECR — a registry API call the pod itself makes, distinct from kubelet's own image pull (which
# already works via the node role's existing ECR permissions, unrelated to this). IRSA is the
# same pattern every other addon needing AWS API access already uses in this repository.

data "aws_iam_policy_document" "ecr_read_assume" {
  for_each = toset(["kyverno-admission-controller", "kyverno-background-controller", "trivy-operator"])

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
      values   = ["system:serviceaccount:${each.key == "trivy-operator" ? "trivy-system" : "kyverno"}:${each.key}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecr_read" {
  for_each = data.aws_iam_policy_document.ecr_read_assume

  name               = "${var.name_prefix}-${each.key}-role"
  assume_role_policy = each.value.json

  tags = merge(var.tags, { Application = "supply-chain-security", Purpose = "${each.key}-irsa-role" })
}

# Read-only, registry-wide (ECR auth tokens are account/region-scoped, not per-repository) —
# every repository this policy can reach still lives under patheya-express/*
# (modules/ecr's own naming), and neither Kyverno nor Trivy Operator can push, delete, or modify
# anything.
data "aws_iam_policy_document" "ecr_read" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken has no per-registry ARN to scope to — the same "unscoped read" pattern already used for Karpenter/ALB Controller/Grafana's CloudWatch policies
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:*:repository/patheya-express/*"]
  }
}

resource "aws_iam_role_policy" "ecr_read" {
  for_each = aws_iam_role.ecr_read

  name   = "${var.name_prefix}-${each.key}-policy"
  role   = each.value.id
  policy = data.aws_iam_policy_document.ecr_read.json
}
