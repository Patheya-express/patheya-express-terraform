# The one role GitHub Actions assumes to run `terraform plan`/`apply` against this account
# (blueprint ADR-006 + ADR-005's GitOps stance — the ONLY sanctioned path to a production change,
# platform-standards.md Section 1 principle 5). No human ever holds a static credential capable of
# the same actions; a human's IAM Identity Center PlatformAdministrator session (modules/organizations)
# is the equivalent break-glass path, itself federated, never a stored access key.

data "aws_iam_policy_document" "terraform_role_trust" {
  statement {
    sid     = "GitHubOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricts to specific repos AND specific refs (var.terraform_role_allowed_branches) — a
    # workflow run from a fork or a feature branch cannot assume this role, only a run against
    # `main` (or whatever protected ref is configured) in an explicitly allow-listed repository.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for repo in var.github_repositories : [
          for ref in var.terraform_role_allowed_branches :
          "repo:${var.github_organization}/${repo}:${ref}"
        ]
      ])
    }
  }
}

resource "aws_iam_role" "terraform" {
  name                 = "${var.name_prefix}-terraform-role"
  assume_role_policy   = data.aws_iam_policy_document.terraform_role_trust.json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = 3600 # 1 hour — a `plan`/`apply` run that needs longer than this is itself worth investigating

  tags = merge(var.tags, { Application = "iam", Purpose = "github-actions-terraform-ci-role" })
}

# Scoped to exactly the AWS services this repository's modules provision (modules/vpc, networking,
# route53, ecr, kms, cloudtrail, config, security, organizations, iam itself) — not
# AdministratorAccess. Explicitly excludes IAM user/access-key creation (defense in depth on top of
# the permission boundary above) and Organizations account deletion/leave.
data "aws_iam_policy_document" "terraform_role_permissions" {
  statement {
    sid    = "InfrastructureProvisioning"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
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
      "logs:*",
      "sns:*",
      "s3:*",
      "dynamodb:*", # state locking table only in practice, but the resource is genuinely account-wide-scoped by IAM's own model
      "organizations:Describe*",
      "organizations:List*",
      "sso:*",
      "sso-directory:*",
      "identitystore:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMRoleAndPolicyManagementForModulesOnly"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:GetRole",
      "iam:ListRole*",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy*",
      "iam:ListPolicy*",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:TagPolicy",
      "iam:UntagRole",
      "iam:UntagPolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:PassRole",
    ]
    resources = ["*"]
  }

  # Explicit deny, redundant with the permission boundary but stated in-policy too — the two
  # controls are independently maintained and a change to one shouldn't silently rely on the other
  # to catch a mistake.
  statement {
    sid    = "ExplicitDenyUserAndKeyCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "organizations:LeaveOrganization",
      "organizations:DeleteOrganization",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_role_permissions" {
  name        = "${var.name_prefix}-terraform-role-policy"
  description = "Infrastructure-provisioning permissions for the GitHub Actions Terraform CI role — scoped to what this repository's modules actually create, not AdministratorAccess."
  policy      = data.aws_iam_policy_document.terraform_role_permissions.json

  tags = merge(var.tags, { Application = "iam", Purpose = "terraform-ci-role-policy" })
}

resource "aws_iam_role_policy_attachment" "terraform" {
  role       = aws_iam_role.terraform.name
  policy_arn = aws_iam_policy.terraform_role_permissions.arn
}
