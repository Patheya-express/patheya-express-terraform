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
# route53, ecr, kms, cloudtrail, config, security, organizations, iam itself, eks, eks-addons,
# aurora, elasticache, backup-vault, secrets-manager) — not AdministratorAccess. Explicitly
# excludes IAM user/access-key creation (defense in depth on top of the permission boundary above)
# and Organizations account deletion/leave.
#
# Phase 0 remediation, three fixes:
#   1. This statement was missing eks:*/rds:*/elasticache:*/backup:*/secretsmanager:* entirely —
#      a real gap, not a hardening choice: this same role is what CI plans and applies
#      environments/<tier>/cluster (EKS) and environments/<tier>/data (Aurora, ElastiCache,
#      Secrets Manager, AWS Backup) against, per .github/workflows/terraform-ci.yml's per-account
#      job matrix (one role per account, reused across every stage). Without these, `apply` against
#      those layers would fail with an authorization error the moment they were ever run for real.
#   2. IAMRoleAndPolicyManagementForModulesOnly's actions were real (title matched intent), but its
#      resources were `["*"]` — account-wide, not "for modules only." iam:PassRole with
#      resources=["*"] in particular is a textbook privilege-escalation primitive (pass any role in
#      the account to any service that accepts one). Scoped below to this account's own naming
#      convention (${var.name_prefix}-*), which every role/policy/instance-profile this
#      repository's modules create already follows.
#   3. (Independent final review, second pass) events:* was also missing — modules/security's
#      GuardDuty/Security Hub EventBridge routing and modules/eks-addons/karpenter.tf's
#      spot-interruption rules both need it; "aws_cloudwatch_event_*" is a resource-naming
#      holdover, the real IAM namespace is "events:", not "cloudwatch:".
data "aws_iam_policy_document" "terraform_role_permissions" {
  statement {
    sid    = "InfrastructureProvisioning"
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
      "events:*", # EventBridge — despite the "aws_cloudwatch_event_*" resource naming (a Terraform/AWS-provider legacy holdover from CloudWatch Events), the actual IAM action namespace is "events:", entirely separate from "cloudwatch:". Needed by modules/security/finding-notifications.tf's GuardDuty/Security Hub routing rules and by the pre-existing modules/eks-addons/karpenter.tf spot-interruption rules — both were unable to apply without this.
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

  # Scoped to this account's own naming convention, not account-wide — see modules/eks/main.tf's
  # aws_iam_role.cluster ("${var.name_prefix}-eks-cluster-role"), modules/eks/node-groups.tf's
  # aws_iam_role.node ("${var.name_prefix}-eks-node-role"), modules/aurora/backup.tf's
  # aws_iam_role.backup ("${var.name_prefix}-aurora-backup-role"), and this same module's own
  # terraform/ECR-push roles — every role this repository creates already follows this pattern.
  statement {
    sid    = "IAMRoleAndPolicyManagementScopedToOwnNamingConvention"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:PassRole",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.name_prefix}-*",
    ]
  }

  statement {
    sid    = "IAMPolicyManagementScopedToOwnNamingConvention"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name_prefix}-*"]
  }

  # OIDC provider (one per account, named by URL) and service-linked roles (AWS-named, e.g.
  # AWSServiceRoleForElastiCache) don't fit the naming-convention pattern above — scoped by action
  # set instead; CreateServiceLinkedRole further restricted to only the services this repository's
  # modules actually provision.
  statement {
    sid    = "IAMOIDCProviderManagement"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "IAMServiceLinkedRoleCreationForOwnedServicesOnly"
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
