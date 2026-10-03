data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  api_image       = "${var.image_repository_url}:${var.image_tag}"
  worker_image    = local.api_image # same image, different container command — never a separate image/repository
  migration_image = "${var.image_repository_url}:${var.image_tag}${var.migration_image_tag_suffix}"

  ci_managed = var.service_management_mode == "ci_autoscaled"

  migration_database_url_secret_arn = coalesce(var.migration_database_url_secret_arn, var.database_url_secret_arn)

  # ECS `secrets` valueFrom may carry a JSON-key suffix (`<secret-arn>:<json-key>::`), but IAM
  # matches the secret's own ARN — the first seven colon-separated fields
  # (arn:partition:secretsmanager:region:account:secret:name-suffix). Normalizing here keeps the
  # execution role scoped to exactly the referenced secrets while accepting either form.
  all_referenced_secret_arns = distinct([
    for ref in concat(
      [var.database_url_secret_arn, local.migration_database_url_secret_arn],
      values(var.app_secrets),
    ) : join(":", slice(split(":", ref), 0, 7))
  ])

  secrets_kms_key_arns = distinct(concat([var.kms_key_arn], var.secrets_kms_key_arns))

  # The shared-services ECR repository when images are pulled cross-account (Production); this
  # account's own repositories otherwise (development-temp's original, unchanged scope).
  ecr_pull_resources = var.image_repository_arn != null ? [var.image_repository_arn] : [
    "arn:${data.aws_partition.current.partition}:ecr:*:${data.aws_caller_identity.current.account_id}:repository/*",
  ]

  api_worker_secrets = concat(
    [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }],
    [for k, v in var.app_secrets : { name = k, valueFrom = v }],
  )

  api_worker_environment = [for k, v in var.app_environment : { name = k, value = v }]

  # Fargate has no tmpfs support — each writable path is an ephemeral task-storage bind mount
  # (a `volume` with no host path) instead. Empty by default, as is every hardening key below:
  # the merged container definitions are byte-identical to the original module output unless a
  # caller opts in, so existing callers see no task-definition replacement.
  writable_volumes = { for idx, path in var.writable_container_paths : "writable-${idx}" => path }

  container_hardening = merge(
    var.readonly_root_filesystem ? { readonlyRootFilesystem = true } : {},
    length(local.writable_volumes) > 0 ? {
      mountPoints = [for name, path in local.writable_volumes : { sourceVolume = name, containerPath = path, readOnly = false }]
    } : {},
    var.stop_timeout_seconds != null ? { stopTimeout = var.stop_timeout_seconds } : {},
    # ECS Exec's SSM agent runs inside the task; an init process reaps its child processes.
    var.enable_execute_command ? { linuxParameters = { initProcessEnabled = true } } : {},
  )

  api_service_name    = "${var.name_prefix}-api"
  worker_service_name = "${var.name_prefix}-worker"
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = var.container_insights
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
    resources = local.ecr_pull_resources
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
    resources = local.secrets_kms_key_arns
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
# managed role, but carry NO business permissions: an IAM role with only an assume-role policy
# and a permissions boundary already grants zero permissions. The one exception is ECS Exec
# (var.enable_execute_command), whose SSM agent channel runs under the task role — that, and
# nothing else, is added below when enabled.

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

# ECS Exec — the SSM Session Manager message channels only (AWS-documented minimum; these actions
# have no resource-level scoping). Access to *start* a session is governed separately by the
# human's own ecs:ExecuteCommand permission, not by this role.
data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid    = "EcsExecSessionChannels"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_task_ecs_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "${var.name_prefix}-ecs-api-task-exec-policy"
  role   = aws_iam_role.api_task.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

resource "aws_iam_role_policy" "worker_task_ecs_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "${var.name_prefix}-ecs-worker-task-exec-policy"
  role   = aws_iam_role.worker_task.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

# --- API task definition ----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.api_cpu)
  memory                   = tostring(var.api_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.api_task.arn

  dynamic "volume" {
    for_each = local.writable_volumes
    content {
      name = volume.key
    }
  }

  container_definitions = jsonencode([
    merge({
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
    }, local.container_hardening)
  ])

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-task-definition" })
}

# --- Worker task definition (no ALB target) --------------------------------------------------------

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name_prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.worker_cpu)
  memory                   = tostring(var.worker_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn

  dynamic "volume" {
    for_each = local.writable_volumes
    content {
      name = volume.key
    }
  }

  container_definitions = jsonencode([
    merge({
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
    }, local.container_hardening)
  ])

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-task-definition" })
}

# --- Services --------------------------------------------------------------------------------------
# Two mutually exclusive variants per service, selected by var.service_management_mode, because
# Terraform `lifecycle.ignore_changes` cannot be conditional:
#
#   "terraform"     (aws_ecs_service.api / .worker) — Terraform owns the task definition revision
#                   (image tag via var.image_tag) and desired_count. development-temp's original
#                   model, unchanged (moved blocks below make the count gating a pure state move).
#   "ci_autoscaled" (aws_ecs_service.api_ci_managed / .worker_ci_managed) — CI owns the task
#                   definition revision (backend-deploy-ecs.yml registers a new revision per
#                   release and updates the service); Application Auto Scaling owns desired_count
#                   within Terraform-owned min/max (autoscaling.tf). Terraform still owns every
#                   other service and task-definition setting.
#
# The two variants' bodies are otherwise identical — keep them in sync.

resource "aws_ecs_service" "api" {
  count = local.ci_managed ? 0 : 1

  name                              = local.api_service_name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.api_desired_count
  launch_type                       = "FARGATE"
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = var.api_health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

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
  # apps/api-gateway/src/modules/realtime/gateways/realtime.gateway.ts's afterInit()), and every
  # client connects websocket-only (frontend realtime-socket.service.ts: transports ['websocket']).

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-service" })
}

resource "aws_ecs_service" "api_ci_managed" {
  count = local.ci_managed ? 1 : 0

  name                              = local.api_service_name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn # initial revision only — see ignore_changes
  desired_count                     = var.api_min_capacity            # initial value only — Application Auto Scaling owns it afterwards
  launch_type                       = "FARGATE"
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = var.api_health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

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

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-service" })

  lifecycle {
    # CI owns the running image revision; Application Auto Scaling owns the task count.
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_ecs_service" "worker" {
  count = local.ci_managed ? 0 : 1

  name                   = local.worker_service_name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.worker.arn
  desired_count          = var.worker_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_execute_command

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_task_security_group_id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-service" })
}

resource "aws_ecs_service" "worker_ci_managed" {
  count = local.ci_managed ? 1 : 0

  name                   = local.worker_service_name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.worker.arn # initial revision only — see ignore_changes
  desired_count          = var.worker_min_capacity            # initial value only — Application Auto Scaling owns it afterwards
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_execute_command

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_task_security_group_id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-service" })

  lifecycle {
    # CI owns the running image revision; Application Auto Scaling owns the task count.
    ignore_changes = [task_definition, desired_count]
  }
}

moved {
  from = aws_ecs_service.api
  to   = aws_ecs_service.api[0]
}

moved {
  from = aws_ecs_service.worker
  to   = aws_ecs_service.worker[0]
}

locals {
  api_service    = local.ci_managed ? aws_ecs_service.api_ci_managed[0] : aws_ecs_service.api[0]
  worker_service = local.ci_managed ? aws_ecs_service.worker_ci_managed[0] : aws_ecs_service.worker[0]
}

# --- Migration task definition (one-off; no service, ever) -----------------------------------------
# Reuses the backend Dockerfile's own `migrate` build stage image
# (ENTRYPOINT ["node_modules/.bin/prisma"] CMD ["migrate","deploy"]) — no new migration mechanism
# invented here. Run via `aws ecs run-task`, from CI or manually, never as a long-running service.
# Its DATABASE_URL is var.migration_database_url_secret_arn when set (Production: the migrator
# user, direct to the Aurora writer) — never the runtime application credential.

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
        { name = "DATABASE_URL", valueFrom = local.migration_database_url_secret_arn }
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
