# GitHub Actions OIDC provider — the entire point of ADR-006 (cloud-architecture-blueprint.md):
# GitHub Actions authenticates to AWS by exchanging a short-lived OIDC token for temporary
# credentials via sts:AssumeRoleWithWebIdentity. No IAM user, no long-lived AWS access key is ever
# stored as a GitHub secret.
#
# The root CA thumbprint is fetched live from GitHub's own OIDC endpoint (via the `tls` provider)
# rather than hardcoded — hand-transcribing a 40-character hex SHA1 thumbprint is exactly how a
# one-character typo (an earlier draft of this file had one) silently breaks OIDC federation. This
# is also the officially recommended pattern: GitHub rotated its intermediate CA once already
# (2023), and a live-fetched thumbprint tracks any future rotation automatically on the next
# `terraform plan` instead of requiring someone to notice federation broke.
data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Root CA thumbprint — the tls_certificate data source orders the chain leaf-first, so the last
  # entry is the root, which is what AWS's OIDC provider registration expects.
  thumbprint_list = [
    data.tls_certificate.github_oidc.certificates[length(data.tls_certificate.github_oidc.certificates) - 1].sha1_fingerprint,
  ]

  tags = merge(var.tags, { Application = "iam", Purpose = "github-actions-oidc-provider" })
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # Computed rather than referencing aws_iam_policy.permission_boundary.arn directly — that
  # resource's own policy document (below) needs to reference this same ARN in a
  # DenyBoundaryTampering condition, which would otherwise be a circular dependency (a resource's
  # policy document referencing that same resource's own computed attribute). IAM policy ARNs are
  # deterministic from account ID + name, so this is exact, not a guess.
  permission_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name_prefix}-permission-boundary"
}

# --- Permission boundary -----------------------------------------------------------------------
# Attached to every Terraform-created human/CI role in this account (starting with the Terraform
# CI role itself, terraform-role.tf) — a hard ceiling on what any role can ever be granted,
# independent of that role's own policy. Defense in depth against privilege escalation: even a
# role with an overly broad policy attached later can't exceed this boundary.
data "aws_iam_policy_document" "permission_boundary" {
  statement {
    sid       = "AllowMostActions"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIAMUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyBoundaryTampering"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.permission_boundary_arn]
    }
  }

  statement {
    sid    = "DenyOrganizationsWriteOutsideManagementModule"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "organizations:DeleteOrganization",
      "organizations:RemoveAccountFromOrganization",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "permission_boundary" {
  name        = "${var.name_prefix}-permission-boundary"
  description = "Ceiling permission boundary for every Terraform-managed role in this account (platform-standards.md Section 1, principle 8)."
  policy      = data.aws_iam_policy_document.permission_boundary.json

  tags = merge(var.tags, { Application = "iam", Purpose = "permission-boundary" })
}
