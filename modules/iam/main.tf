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
# CI role itself, terraform-role.tf, and the ECR-push roles in github-actions-ci-roles.tf) — a hard
# ceiling on what any role can ever be granted, independent of that role's own policy. Defense in
# depth against privilege escalation: even a role with an overly broad policy attached later can't
# exceed this boundary.
#
# Phase 0 remediation: the previous version of this document was a single `AllowMostActions
# actions=["*"] resources=["*"]` statement plus three narrow denies — in practice an "allow
# everything except a handful of escape hatches" boundary, not a meaningful ceiling. A permission
# boundary's entire value is bounding blast radius; one that allows `*` bounds almost nothing.
#
# This version replaces the blanket allow with:
#   1. An explicit allow-list of the AWS services this repository's modules actually provision
#      (kept in sync with terraform-role.tf's own InfrastructureProvisioning statement — the
#      boundary must be at least as broad as what the Terraform CI role is trusted to do, since
#      every environment/layer in this repository plans and applies through that one role, or a
#      legitimate module stops working the moment this boundary is attached).
#   2. IAM management actions scoped by this account's own naming convention
#      (${var.name_prefix}-*) rather than a blanket `iam:*` — every role, policy, and instance
#      profile this repository's modules create already follows that convention (verified against
#      modules/eks, modules/iam itself, modules/aurora's backup role, etc.), so this is a real
#      restriction, not a cosmetic one.
#   3. The AWS-documented escalation guard: creating or re-bounding a role is denied unless that
#      role is given this exact same boundary — closes the "create an unbounded role, pass it,
#      operate outside the boundary" escalation path a blanket `Allow *:*` boundary leaves open.
#   4. The three original denies, unchanged (IAM user/access-key creation, boundary
#      self-tampering, leaving/deleting the organization).
data "aws_iam_policy_document" "permission_boundary" {
  statement {
    sid    = "AllowInfrastructureServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "eks:*",
      "rds:*",
      "elasticache:*",
      "backup:*",
      "secretsmanager:*",
      "route53:*",
      "route53domains:*",
      "acm:*",
      "ecr:*",
      "kms:*",
      "cloudtrail:*",
      "config:*",
      "guardduty:*",
      "securityhub:*",
      "access-analyzer:*",
      "budgets:*",
      "cloudwatch:*",
      "events:*", # EventBridge — separate IAM namespace from "cloudwatch:" despite the "aws_cloudwatch_event_*" resource naming. Kept symmetric with terraform-role.tf's InfrastructureProvisioning statement, which needs this for the same reason.
      "logs:*",
      "sns:*",
      "s3:*",
      "dynamodb:*",
      "organizations:Describe*",
      "organizations:List*",
      "sso:*",
      "sso-directory:*",
      "identitystore:*",
    ]
    resources = ["*"]
  }

  # Scoped to this account's own naming convention — never a blanket iam:* the way the boundary's
  # own attached roles would otherwise be free to escalate through.
  statement {
    sid    = "AllowScopedIAMRoleAndPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:TagRole", "iam:UntagRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile", "iam:GetInstanceProfile", "iam:TagInstanceProfile",
      "iam:PassRole",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.name_prefix}-*",
    ]
  }

  statement {
    sid    = "AllowScopedIAMPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name_prefix}-*"]
  }

  # OIDC provider and service-linked-role actions don't fit the role/policy naming-convention
  # pattern above (an OIDC provider is one per account, named by URL; service-linked roles are
  # AWS-named, e.g. AWSServiceRoleForElastiCache) — scoped by action set instead, and
  # CreateServiceLinkedRole further scoped to only the services this repository's modules
  # provision (EKS, its managed node groups, ElastiCache, RDS, Backup, EC2 Spot for Karpenter).
  statement {
    sid    = "AllowOIDCProviderManagement"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:TagOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowServiceLinkedRoleCreationForOwnedServicesOnly"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "elasticache.amazonaws.com",
        "rds.amazonaws.com",
        "backup.amazonaws.com",
        "spot.amazonaws.com",
      ]
    }
  }

  # Escalation guard (the AWS-documented pattern for permission-boundary-bounded CI roles): a role
  # bounded by this policy may only create or re-bound another role if that role is given this
  # exact same boundary. Without this, a role otherwise limited by AllowScopedIAMRoleAndPolicyManagement
  # above could still create a *new*, unbounded role and pass/assume it to operate outside this
  # ceiling entirely.
  statement {
    sid    = "RequireThisBoundaryOnRolesCreatedOrRebounded"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
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

  # Defense in depth: none of the Allow statements above ever grant these actions, so this deny is
  # redundant today by construction — kept explicit so a future edit that widens an Allow
  # statement's action list can't silently reopen a classic IAM privilege-escalation vector
  # (creating/attaching policy to an IAM *user* or *group*, which this account has none of by
  # design — modules/organizations' SCPs and this module's own DenyIAMUserCreation statement both
  # already assume that's permanently true).
  statement {
    sid    = "DenyKnownEscalationVectorsOnUsersAndGroups"
    effect = "Deny"
    actions = [
      "iam:AttachUserPolicy", "iam:PutUserPolicy",
      "iam:AttachGroupPolicy", "iam:PutGroupPolicy",
      "iam:CreateLoginProfile", "iam:UpdateLoginProfile",
      "iam:AddUserToGroup", "iam:CreateGroup",
    ]
    resources = ["*"]
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
