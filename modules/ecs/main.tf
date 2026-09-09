data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  api_image       = "${var.image_repository_url}:${var.image_tag}"
  worker_image    = local.api_image # same image, different container command — never a separate image/repository
  migration_image = "${var.image_repository_url}:${var.image_tag}${var.migration_image_tag_suffix}"

  # Every secret ARN any container in this module might reference — the execution role needs
  # secretsmanager:GetSecretValue on exactly this set (and nothing else) to resolve ECS `secrets`
  # at container launch. Deduplicated via a set conversion since database_url_secret_arn and
  # app_secrets could theoretically overlap.
  all_referenced_secret_arns = distinct(concat([var.database_url_secret_arn], values(var.app_secrets)))

  api_worker_secrets = concat(
    [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }],
    [for k, v in var.app_secrets : { name = k, valueFrom = v }],
  )

  api_worker_environment = [for k, v in var.app_environment : { name = k, value = v }]
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "disabled" # deliberately minimal observability for temporary DEV+QA (Phase 1 §14) — not overbuilding for a scale that doesn't need it
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "ecs-cluster" })
}

# --- CloudWatch log groups -----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/patheya-express/${var.environment}/ecs/api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-task-logs" })
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/patheya-express/${var.environment}/ecs/worker"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-task-logs" })
}

resource "aws_cloudwatch_log_group" "migration" {
  name              = "/patheya-express/${var.environment}/ecs/migration"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "migration-task-logs" })
}

# --- ECS execution role (shared) ------------------------------------------------------------------
# Pulls container images from ECR, writes to CloudWatch Logs, and resolves the `secrets` block of
# every task definition below at container launch — this is infrastructure-level access, not
# business-logic access, hence one shared role rather than one per task definition (contrast with
# the three distinct, narrowly-scoped TASK roles below, which are per-task-definition).

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
  name                 = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy   = data.aws_iam_policy_document.execution_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "ecs-execution-role" })
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"] # GetAuthorizationToken does not support resource-level scoping — an AWS-documented exception, not a broadening of this policy's intent
  }

  statement {
    sid    = "ECRPullScoped"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:*:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  statement {
    sid    = "WriteOwnLogStreams"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.api.arn}:*",
      "${aws_cloudwatch_log_group.worker.arn}:*",
      "${aws_cloudwatch_log_group.migration.arn}:*",
    ]
  }

  statement {
    sid       = "ResolveTaskDefinitionSecretsOnly"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.all_referenced_secret_arns
  }

  statement {
    sid       = "DecryptTaskDefinitionSecrets"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name_prefix}-ecs-execution-policy"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# --- Task roles (one per task definition, least privilege) ---------------------------------------
# The application makes no direct AWS API calls at runtime today (storage is Cloudinary, not S3;
# no other AWS SDK usage found in apps/api-gateway/src) — these roles exist because ECS requires a
# task role and are bounded by the same account permission boundary as every other Terraform-
# managed role, but deliberately carry NO inline policy: an IAM role with only an assume-role
# policy and a permissions boundary already grants zero permissions, which is exactly the correct,
# auditable state today. A policy is added here only when the application genuinely needs one —
# not invented ahead of need.

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

resource "aws_iam_role" "api_task" {
  name                 = "${var.name_prefix}-ecs-api-task-role"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-task-role" })
}

resource "aws_iam_role" "worker_task" {
  name                 = "${var.name_prefix}-ecs-worker-task-role"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-task-role" })
}

resource "aws_iam_role" "migration_task" {
  name                 = "${var.name_prefix}-ecs-migration-task-role"
  assume_role_policy   = data.aws_iam_policy_document.task_assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "ecs", Purpose = "migration-task-role" })
}

# --- API task definition + service --------------------------------------------------------------

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.api_cpu)
  memory                   = tostring(var.api_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.api_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.api_image
      essential = true
      portMappings = [
        { containerPort = var.api_container_port, protocol = "tcp" }
      ]
      environment = local.api_worker_environment
      secrets     = local.api_worker_secrets
      healthCheck = {
        # Matches the backend Dockerfile's own HEALTHCHECK target — not a new check invented here.
        command     = ["CMD-SHELL", "wget -q -O- http://localhost:${var.api_container_port}${var.liveness_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "api"
        }
      }
    }
  ])

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-task-definition" })
}

data "aws_region" "current" {}

resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_task_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "api"
    container_port   = var.api_container_port
  }

  # No sticky sessions configured anywhere in this module or module.alb — safe because the
  # application's Socket.IO Redis adapter already fans events out across instances (confirmed:
  # apps/api-gateway/src/modules/realtime/gateways/realtime.gateway.ts's afterInit()).

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-service" })
}

# --- Worker task definition + service (no ALB target) ---------------------------------------------

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name_prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.worker_cpu)
  memory                   = tostring(var.worker_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn

  container_definitions = jsonencode([
    {
      name        = "worker"
      image       = local.worker_image
      essential   = true
      command     = ["node", "dist/src/worker-main.js"]
      environment = local.api_worker_environment
      secrets     = local.api_worker_secrets
      healthCheck = {
        # The worker still calls app.listen() purely to serve this endpoint (confirmed:
        # apps/api-gateway/src/worker-main.ts) — no ALB target, container-level check only.
        command     = ["CMD-SHELL", "wget -q -O- http://localhost:${var.api_container_port}${var.liveness_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-task-definition" })
}

resource "aws_ecs_service" "worker" {
  name            = "${var.name_prefix}-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_task_security_group_id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-service" })
}

# --- Migration task definition (one-off; no service, ever) -----------------------------------------
# Reuses the backend Dockerfile's own `migrate` build stage image
# (ENTRYPOINT ["node_modules/.bin/prisma"] CMD ["migrate","deploy"]) — no new migration mechanism
# invented here. Run via `aws ecs run-task`, from CI or manually, never as a long-running service.

resource "aws_ecs_task_definition" "migration" {
  family                   = "${var.name_prefix}-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.migration_cpu)
  memory                   = tostring(var.migration_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.migration_task.arn

  container_definitions = jsonencode([
    {
      name      = "migrate"
      image     = local.migration_image
      essential = true
      # No command/entryPoint override — the -migrate image's own ENTRYPOINT/CMD
      # (prisma migrate deploy) runs unmodified.
      secrets = [
        { name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.migration.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "migrate"
        }
      }
    }
  ])

  tags = merge(var.tags, { Application = "ecs", Purpose = "migration-task-definition" })
}
