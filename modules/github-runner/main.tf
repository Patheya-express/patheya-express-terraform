# Self-hosted GitHub Actions runner, living inside the Production VPC - the CI/CD path to the
# private EKS API endpoint. Needs no Tailscale: placed in a private-app subnet, it already has
# ordinary VPC-internal network reachability to the EKS control-plane ENIs (same subnets, same
# reasoning as modules/tailscale-router). AWS API calls a workflow job makes still go through the
# EXISTING GitHub OIDC -> module.iam.aws_iam_role.terraform assumption (patheya-express-terraform's
# own trust policy, unchanged) - self-hosting only solves network reachability to the K8s API, not
# AWS authentication, which was never the problem.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- Secret (empty container; a human populates the value out-of-band with a GitHub PAT scoped to
# exactly var.github_repository's admin:org or repo-scope registration permission - see this
# module's README for the exact scope required) ------------------------------------------------

resource "aws_secretsmanager_secret" "github_pat" {
  name        = "patheya-express/production/github-runner-pat"
  description = "GitHub PAT used by the self-hosted runner to register/deregister itself against ${var.github_repository} - value populated out-of-band by a human via `aws secretsmanager put-secret-value`, never by Terraform. Fine-grained PAT, repository-scoped to exactly this one repo, Administration:write permission only."
  kms_key_id  = var.kms_key_arn

  tags = merge(var.tags, { Application = "github-runner", Purpose = "github-pat" })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/patheya-express/production/github-runner"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "github-runner", Purpose = "runner-logs" })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-github-runner"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(var.tags, { Application = "github-runner", Purpose = "ecs-cluster" })
}

# --- IAM: execution role (pulls the runner image, writes logs, reads its own PAT secret) -------

data "aws_iam_policy_document" "execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name                 = "${var.name_prefix}-github-runner-execution-role"
  assume_role_policy   = data.aws_iam_policy_document.execution_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "github-runner", Purpose = "execution-role" })
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # AWS-documented exception - GetAuthorizationToken has no resource-level scoping
  }

  statement {
    sid    = "WriteOwnLogStream"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "ResolveOwnPATSecretOnly"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.github_pat.arn]
  }

  statement {
    sid       = "DecryptOwnSecret"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name_prefix}-github-runner-execution-policy"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# --- IAM: task role - deliberately empty (assume-role policy + permission boundary only,
# identical reasoning to modules/ecs's api_task/worker_task roles). AWS API calls a workflow job
# makes go through the job's own GitHub-OIDC-assumed role, not this task role - this role exists
# only because ECS requires one. -----------------------------------------------------------------

data "aws_iam_policy_document" "task_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name                 = "${var.name_prefix}-github-runner-task-role"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "github-runner", Purpose = "task-role" })
}

# --- Security group - egress-only. The runner never accepts inbound connections; it polls GitHub
# for jobs. -----------------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name_prefix = "${var.name_prefix}-github-runner-"
  description = "Self-hosted GitHub Actions runner - outbound only, no inbound from anywhere."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-github-runner-sg"
    Application = "github-runner"
    Purpose     = "github-runner-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https_internet" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to GitHub API/Actions endpoints and AWS APIs, via NAT - no fixed IP range on GitHub side."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Task definition + service -------------------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-github-runner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "runner"
      image     = var.runner_image
      essential = true
      environment = [
        { name = "REPO_URL", value = "https://github.com/${var.github_repository}" },
        { name = "RUNNER_SCOPE", value = "repo" },
        { name = "LABELS", value = join(",", var.runner_labels) },
        { name = "EPHEMERAL", value = "true" }, # a fresh runner per job - no state persists between jobs, no risk of a compromised job affecting the next one
      ]
      secrets = [
        { name = "ACCESS_TOKEN", valueFrom = aws_secretsmanager_secret.github_pat.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "runner"
        }
      }
    }
  ])

  tags = merge(var.tags, { Application = "github-runner", Purpose = "runner-task-definition" })
}

resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-github-runner"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0 # ephemeral runners are expected to exit after each job and be replaced - not a rolling-update-style service
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Application = "github-runner", Purpose = "runner-service" })
}
