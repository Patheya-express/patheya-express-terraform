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

# --- Production application deploy roles (ECS + static web) ------------------------------------
# Created only where var.ecs_deploy / var.static_site_deploy are set (Production). Both trust ONLY
# workflow jobs running in the named GitHub Environment (OIDC `sub` =
# repo:<org>/<repo>:environment:<name>), so the environment's required-reviewer protection rule
# is the manual approval gate and no unreviewed branch or PR can assume either role.
#
# Neither role can run Terraform, change infrastructure, or touch IAM beyond iam:PassRole of the
# exact ECS roles. Terraform owns the infrastructure; these roles own only the application
# revision (ECS task definition / static files).

data "aws_region" "current" {}

locals {
  regional_arn_prefix = "${data.aws_partition.current.partition}:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}"
  logs_arn_prefix     = "${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_policy_document" "backend_ecs_deploy_trust" {
  count = var.ecs_deploy != null ? 1 : 0

  statement {
    sid     = "GitHubOIDCAssumeRoleBackendDeploy"
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
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_organization}/${var.backend_github_repository}:environment:${var.ecs_deploy.github_environment}"]
    }
  }
}

resource "aws_iam_role" "backend_ecs_deploy" {
  count = var.ecs_deploy != null ? 1 : 0

  name                 = "${var.name_prefix}-backend-ecs-deploy-role"
  assume_role_policy   = data.aws_iam_policy_document.backend_ecs_deploy_trust[0].json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, { Application = "api-gateway", Purpose = "github-actions-backend-ecs-deploy-role" })
}

data "aws_iam_policy_document" "backend_ecs_deploy_permissions" {
  count = var.ecs_deploy != null ? 1 : 0

  # Task-definition registration and description have no resource-level scoping in the ECS API.
  statement {
    sid       = "TaskDefinitionRegistration"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  # A new revision carries the previous revision's tags forward; tagging is permitted only as part
  # of that registration, never on an existing resource.
  statement {
    sid       = "TagOnlyOnRegistration"
    effect    = "Allow"
    actions   = ["ecs:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }

  statement {
    sid     = "UpdateAndWatchServices"
    effect  = "Allow"
    actions = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [
      for service in var.ecs_deploy.service_names :
      "arn:${local.regional_arn_prefix}:service/${var.ecs_deploy.cluster_name}/${service}"
    ]
  }

  # The migration task family only, and only in this cluster.
  statement {
    sid       = "RunMigrationTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["arn:${local.regional_arn_prefix}:task-definition/${var.ecs_deploy.migration_task_family}:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["arn:${local.regional_arn_prefix}:cluster/${var.ecs_deploy.cluster_name}"]
    }
  }

  statement {
    sid       = "WatchTasks"
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:${local.regional_arn_prefix}:task/${var.ecs_deploy.cluster_name}/*"]
  }

  statement {
    sid     = "PassOnlyTheEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      for role in var.ecs_deploy.pass_role_names :
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${role}"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Read the migration task's output so a failed migration is diagnosable from the workflow log.
  statement {
    sid       = "ReadMigrationLogs"
    effect    = "Allow"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:${local.logs_arn_prefix}:log-group:${var.ecs_deploy.migration_log_group_name}:*"]
  }

  # Resolve the release tag to its digest and verify its cosign signature — read-only, against the
  # one shared-services repository (whose repository policy grants this account pull access).
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrReadReleaseImage"
    effect    = "Allow"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [var.ecs_deploy.image_repository_arn]
  }
}

resource "aws_iam_policy" "backend_ecs_deploy_permissions" {
  count = var.ecs_deploy != null ? 1 : 0

  name        = "${var.name_prefix}-backend-ecs-deploy-policy"
  description = "GitHub Actions (patheya-express-platform, ${var.ecs_deploy.github_environment} environment) - register task definitions, run the migration task, update the API/worker services."
  policy      = data.aws_iam_policy_document.backend_ecs_deploy_permissions[0].json

  tags = merge(var.tags, { Application = "api-gateway", Purpose = "backend-ecs-deploy-role-policy" })
}

resource "aws_iam_role_policy_attachment" "backend_ecs_deploy" {
  count = var.ecs_deploy != null ? 1 : 0

  role       = aws_iam_role.backend_ecs_deploy[0].name
  policy_arn = aws_iam_policy.backend_ecs_deploy_permissions[0].arn
}

# --- Frontend static web deploy ---------------------------------------------------------------------

data "aws_iam_policy_document" "frontend_static_deploy_trust" {
  count = var.static_site_deploy != null ? 1 : 0

  statement {
    sid     = "GitHubOIDCAssumeRoleFrontendDeploy"
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
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_organization}/${var.frontend_github_repository}:environment:${var.static_site_deploy.github_environment}"]
    }
  }
}

resource "aws_iam_role" "frontend_static_deploy" {
  count = var.static_site_deploy != null ? 1 : 0

  name                 = "${var.name_prefix}-frontend-static-deploy-role"
  assume_role_policy   = data.aws_iam_policy_document.frontend_static_deploy_trust[0].json
  permissions_boundary = local.permission_boundary_arn
  max_session_duration = 3600

  tags = merge(var.tags, { Application = "frontend", Purpose = "github-actions-frontend-static-deploy-role" })
}

data "aws_iam_policy_document" "frontend_static_deploy_permissions" {
  count = var.static_site_deploy != null ? 1 : 0

  statement {
    sid       = "ListSiteBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [for name in var.static_site_deploy.bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${name}"]
  }

  # `aws s3 sync --delete` needs Put + Delete; Get lets sync compare existing objects.
  statement {
    sid       = "SyncSiteObjects"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
    resources = [for name in var.static_site_deploy.bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${name}/*"]
  }

  # CloudFront generates distribution IDs, so this is scoped to this account's distributions that
  # carry modules/static-site's own tags rather than to a not-yet-known ID. Fails closed: an
  # untagged or differently-tagged distribution never matches.
  statement {
    sid       = "InvalidateSiteDistributions"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["arn:${data.aws_partition.current.partition}:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Application"
      values   = ["static-site"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.static_site_deploy.environment_tag]
    }
  }
}

resource "aws_iam_policy" "frontend_static_deploy_permissions" {
  count = var.static_site_deploy != null ? 1 : 0

  name        = "${var.name_prefix}-frontend-static-deploy-policy"
  description = "GitHub Actions (frontend, ${var.static_site_deploy.github_environment} environment) - sync the static-site buckets and invalidate their CloudFront distributions."
  policy      = data.aws_iam_policy_document.frontend_static_deploy_permissions[0].json

  tags = merge(var.tags, { Application = "frontend", Purpose = "frontend-static-deploy-role-policy" })
}

resource "aws_iam_role_policy_attachment" "frontend_static_deploy" {
  count = var.static_site_deploy != null ? 1 : 0

  role       = aws_iam_role.frontend_static_deploy[0].name
  policy_arn = aws_iam_policy.frontend_static_deploy_permissions[0].arn
}
