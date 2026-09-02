# Phase 8 (Enterprise CI/CD Platform): the application repos' own image-push OIDC roles —
# explicitly deferred by environments/shared-services/main.tf's original module.iam call ("added
# in Phase 7 (GitOps) alongside the rest of that CI/CD wiring" — that comment predates this
# repository's actual phase numbering settling on Phase 8 for CI/CD; the deferral itself was
# correct, only the phase label written at the time wasn't). Two roles, not one shared role — the
# backend and frontend repos are different GitHub repositories with different, non-overlapping ECR
# repositories to push to, and platform-standards.md Section 1 principle 8 (least privilege) means
# neither workflow should be able to push the other's images.

data "aws_iam_policy_document" "backend_ecr_push_trust" {
  statement {
    sid     = "GitHubOIDCAssumeRoleBackend"
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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for ref in var.app_release_allowed_branches :
        "repo:${var.github_organization}/${var.backend_github_repository}:${ref}"
      ]
    }
  }
}

# Phase 0 remediation: count-gated on backend_ecr_repository_arns actually being non-empty. An
# aws_iam_policy_document statement with `resources = []` (what var.backend_ecr_repository_arns
# defaults to in every account except shared-services) is invalid at apply time — IAM rejects a
# policy statement with zero resources — so this role, its policy, and its attachment simply don't
# exist in an account that doesn't own the ECR repositories to push to, rather than existing with
# a policy that can never actually match anything.
resource "aws_iam_role" "backend_ecr_push" {
  count = length(var.backend_ecr_repository_arns) > 0 ? 1 : 0

  name                 = "${var.name_prefix}-backend-ecr-push-role"
  assume_role_policy   = data.aws_iam_policy_document.backend_ecr_push_trust.json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, { Application = "api-gateway", Purpose = "github-actions-backend-ecr-push-role" })
}

# ecr:GetAuthorizationToken has no resource-level scoping in the ECR API (it's account-wide by
# AWS's own design, not a gap in this policy) — every other action is scoped to exactly the one
# repository this role's workflow publishes to.
data "aws_iam_policy_document" "backend_ecr_push_permissions" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushApiGateway"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.backend_ecr_repository_arns
  }
}

resource "aws_iam_policy" "backend_ecr_push_permissions" {
  count = length(var.backend_ecr_repository_arns) > 0 ? 1 : 0

  name        = "${var.name_prefix}-backend-ecr-push-policy"
  description = "GitHub Actions (patheya-express-platform, main branch only) — push access to the api-gateway ECR repository only."
  policy      = data.aws_iam_policy_document.backend_ecr_push_permissions.json

  tags = merge(var.tags, { Application = "api-gateway", Purpose = "backend-ecr-push-role-policy" })
}

resource "aws_iam_role_policy_attachment" "backend_ecr_push" {
  count = length(var.backend_ecr_repository_arns) > 0 ? 1 : 0

  role       = aws_iam_role.backend_ecr_push[0].name
  policy_arn = aws_iam_policy.backend_ecr_push_permissions[0].arn
}

# --- Frontend --------------------------------------------------------------------------------

data "aws_iam_policy_document" "frontend_ecr_push_trust" {
  statement {
    sid     = "GitHubOIDCAssumeRoleFrontend"
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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for ref in var.app_release_allowed_branches :
        "repo:${var.github_organization}/${var.frontend_github_repository}:${ref}"
      ]
    }
  }
}

resource "aws_iam_role" "frontend_ecr_push" {
  count = length(var.frontend_ecr_repository_arns) > 0 ? 1 : 0

  name                 = "${var.name_prefix}-frontend-ecr-push-role"
  assume_role_policy   = data.aws_iam_policy_document.frontend_ecr_push_trust.json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, { Application = "frontend", Purpose = "github-actions-frontend-ecr-push-role" })
}

data "aws_iam_policy_document" "frontend_ecr_push_permissions" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushFrontendApps"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.frontend_ecr_repository_arns
  }
}

resource "aws_iam_policy" "frontend_ecr_push_permissions" {
  count = length(var.frontend_ecr_repository_arns) > 0 ? 1 : 0

  name        = "${var.name_prefix}-frontend-ecr-push-policy"
  description = "GitHub Actions (frontend repo, main branch only) — push access to the four frontend app ECR repositories only, never api-gateway."
  policy      = data.aws_iam_policy_document.frontend_ecr_push_permissions.json

  tags = merge(var.tags, { Application = "frontend", Purpose = "frontend-ecr-push-role-policy" })
}

resource "aws_iam_role_policy_attachment" "frontend_ecr_push" {
  count = length(var.frontend_ecr_repository_arns) > 0 ? 1 : 0

  role       = aws_iam_role.frontend_ecr_push[0].name
  policy_arn = aws_iam_policy.frontend_ecr_push_permissions[0].arn
}
