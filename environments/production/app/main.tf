# Production application layer — the ECS Fargate runtime and its public edge. Replaces the retired
# cluster/ (EKS) and platform/ (Kubernetes add-ons, ArgoCD, in-cluster observability) layers.
#
#   root (production/terraform.tfstate)  VPC, security groups, IAM/OIDC + CI deploy roles
#   data (production/data/...)           Aurora, RDS Proxy, ElastiCache, Secrets Manager
#   app  (this layer)                    ALB + ACM + WAF, ECS cluster/services/task definitions,
#                                        static web (S3 + CloudFront), Production DNS records
#
# This layer creates no network or database resources — it only consumes root and data outputs.
# It requires the data layer's state in every mode (task definitions reference its secrets).

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/terraform.tfstate"
    region = "ap-south-1"
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/data/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "production"
  application = "ecs-app"
  purpose     = "Production ECS Fargate application runtime, public edge and static web"
  retention   = "n/a"
}

locals {
  network = data.terraform_remote_state.network.outputs
  data    = data.terraform_remote_state.data.outputs

  api_domain = "${var.api_hostname}.${var.apex_domain}"
  site_domains = {
    for site, label in var.static_sites : site => "${label}.${var.apex_domain}"
  }

  # Per-mode capacity — explicit rows, no derived math (same convention as the root layer).
  # Sizes are fixed across modes so build exercises the exact live task shapes.
  #   API    1 vCPU / 2 GB   — the k8s production overlay's limits (2 CPU / 1 Gi) mapped to the
  #                            nearest Fargate size that holds the 1 Gi heap with headroom.
  #   worker 0.5 vCPU / 1 GB — the overlay's worker limits (1 CPU / 768 Mi), same mapping.
  # Live bounds are NOT the old HPA ceilings (API 15 / worker 12): with deployment surge those
  # could need ~42 vCPU against a 30 vCPU Fargate quota. See the fargate_peak_vcpu output.
  capacity_by_mode = {
    idle  = { api_min = 0, api_max = 0, worker_min = 0, worker_max = 0, api_alarm = null, worker_alarm = null }
    build = { api_min = 1, api_max = 1, worker_min = 1, worker_max = 1, api_alarm = 1, worker_alarm = 1 }
    live  = { api_min = 2, api_max = 6, worker_min = 1, worker_max = 3, api_alarm = 2, worker_alarm = 1 }
  }
  capacity = local.capacity_by_mode[var.operating_mode]

  task_size = {
    api_cpu       = 1024
    api_memory    = 2048
    worker_cpu    = 512
    worker_memory = 1024
    migration_cpu = 256
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Worst case during a rolling deployment of both services at live max capacity, plus one
  # concurrently running migration task.
  live_peak_vcpu = (
    (local.capacity_by_mode.live.api_max * local.task_size.api_cpu + local.capacity_by_mode.live.worker_max * local.task_size.worker_cpu)
    / 1024 * local.deployment_maximum_percent / 100
    + local.task_size.migration_cpu / 1024
  )

  image_repository_url = "${var.shared_services_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/patheya-express/api-gateway"

  # Same JSON-key convention as development-temp's ECS wiring (and the retired ExternalSecret
  # templates) — shapes documented in docs/production-database-bootstrap.md.
  external_secret_arns = local.data.external_credential_secret_arns

  app_secrets = {
    JWT_ACCESS_SECRET           = "${local.external_secret_arns["jwt-signing-key"]}:accessSecret::"
    JWT_REFRESH_SECRET          = "${local.external_secret_arns["jwt-signing-key"]}:refreshSecret::"
    CLOUDINARY_CLOUD_NAME       = "${local.external_secret_arns["cloudinary"]}:cloudName::"
    CLOUDINARY_API_KEY          = "${local.external_secret_arns["cloudinary"]}:apiKey::"
    CLOUDINARY_API_SECRET       = "${local.external_secret_arns["cloudinary"]}:apiSecret::"
    RAZORPAY_KEY_ID             = "${local.external_secret_arns["razorpay"]}:keyId::"
    RAZORPAY_KEY_SECRET         = "${local.external_secret_arns["razorpay"]}:keySecret::"
    RAZORPAY_WEBHOOK_SECRET     = "${local.external_secret_arns["razorpay"]}:webhookSecret::"
    SMTP_HOST                   = "${local.external_secret_arns["smtp"]}:host::"
    SMTP_PORT                   = "${local.external_secret_arns["smtp"]}:port::"
    SMTP_USER                   = "${local.external_secret_arns["smtp"]}:user::"
    SMTP_PASS                   = "${local.external_secret_arns["smtp"]}:pass::"
    SMTP_FROM                   = "${local.external_secret_arns["smtp"]}:from::"
    BANK_ACCOUNT_ENCRYPTION_KEY = local.external_secret_arns["bank-account-encryption-key"]
    SUPER_ADMIN_EMAIL           = "${local.external_secret_arns["super-admin-bootstrap"]}:email::"
    SUPER_ADMIN_PASSWORD        = "${local.external_secret_arns["super-admin-bootstrap"]}:password::"
    SUPER_ADMIN_FIRST_NAME      = "${local.external_secret_arns["super-admin-bootstrap"]}:firstName::"
    SUPER_ADMIN_LAST_NAME       = "${local.external_secret_arns["super-admin-bootstrap"]}:lastName::"
    SUPER_ADMIN_PHONE           = "${local.external_secret_arns["super-admin-bootstrap"]}:phone::"
    REDIS_AUTH_TOKEN            = local.data.redis_auth_token_secret_arn
  }

  app_environment = {
    NODE_ENV            = "production"
    PORT                = "3000"
    STORAGE_DRIVER      = "cloudinary"
    LOG_LEVEL           = "info"
    LOG_TO_FILE         = "false"          # stdout only -> awslogs; also what lets the root filesystem be read-only
    SHUTDOWN_TIMEOUT_MS = "10000"          # below the 30s stopTimeout
    KAFKA_BROKER        = "localhost:9092" # dead config — no Kafka client exists in the application, but env.validation.ts requires the variable
    CUSTOMER_APP_URL    = "https://${local.site_domains["customer"]}"
    RESTAURANT_APP_URL  = "https://${local.site_domains["restaurant"]}"
    ADMIN_APP_URL       = "https://${local.site_domains["admin"]}"
    DELIVERY_APP_URL    = "https://${local.site_domains["delivery"]}"
    API_PUBLIC_URL      = "https://${local.api_domain}"
    # Capacitor WebView origins of the mobile apps — Android (androidScheme: 'https') and iOS.
    # Honored by both the REST CORS allowlist and the realtime gateway.
    EXTRA_ALLOWED_ORIGINS = "https://localhost,capacitor://localhost"
    REDIS_HOST            = local.data.redis_primary_endpoint
    REDIS_PORT            = tostring(local.data.redis_port)
    REDIS_TLS             = "true"
    # Global per-client-IP requests per 60 s (api-gateway rate-limit.config.ts). 100 is normal
    # production; anything else is a temporary load-test override — see rate-limit.auto.tfvars.
    RATE_LIMIT_MAX = tostring(var.api_rate_limit_max)
  }
}

# --- KMS + alert topic --------------------------------------------------------------------------------

module "kms" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    application = {
      description         = "Encrypts the ECS task log groups, the WAF log group and the application alert topic"
      additional_services = ["logs.amazonaws.com", "sns.amazonaws.com", "cloudwatch.amazonaws.com"]
      key_administrators  = [local.network.terraform_role_arn]
    }
  }
}

# Email subscriptions come from alert_email_subscriptions (git-ignored terraform.tfvars), like the
# data layer's topic; AWS emails each address a confirmation link before delivering anything.
module "alerting" {
  source = "../../../modules/alerting"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["application"]
  topic_name  = "alerts-application"

  email_subscriptions = var.alert_email_subscriptions
}

# --- ECS ---------------------------------------------------------------------------------------------

module "ecs" {
  source = "../../../modules/ecs"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "production"

  private_app_subnet_ids     = local.network.private_app_subnet_ids
  ecs_task_security_group_id = local.network.ecs_task_security_group_id
  alb_target_group_arn       = module.alb.target_group_arn

  image_repository_url = local.image_repository_url
  image_repository_arn = local.network.shared_services_api_gateway_repository_arn
  image_tag            = var.bootstrap_image_tag

  kms_key_arn          = module.kms.key_arns["application"]
  secrets_kms_key_arns = [local.data.secrets_kms_key_arn]

  database_url_secret_arn           = local.data.database_url_secret_arn
  migration_database_url_secret_arn = local.data.database_migration_url_secret_arn
  app_secrets                       = local.app_secrets
  app_environment                   = local.app_environment

  api_cpu       = local.task_size.api_cpu
  api_memory    = local.task_size.api_memory
  worker_cpu    = local.task_size.worker_cpu
  worker_memory = local.task_size.worker_memory
  migration_cpu = local.task_size.migration_cpu

  service_management_mode = "ci_autoscaled"
  api_min_capacity        = local.capacity.api_min
  api_max_capacity        = local.capacity.api_max
  worker_min_capacity     = local.capacity.worker_min
  worker_max_capacity     = local.capacity.worker_max

  # Load-test baseline (loadtest/k6/results/phase5-2026-10-08): one 1-vCPU API task costs ~2% CPU
  # per request/s and saturates near 40 rps; ~25-30 rps is comfortable. 50% CPU or 1200 requests
  # per task per minute (20 rps) both scale out well before that ceiling. Aurora, the proxy and
  # Redis were not the bottleneck at the single-task ceiling; live max 6 API tasks stays inside
  # their headroom and the Fargate quota (fargate_peak_vcpu precondition).
  api_autoscaling_cpu_target_percent    = 50
  worker_autoscaling_cpu_target_percent = 60
  api_alb_request_count_target          = 1200
  api_alb_resource_label                = "${module.alb.alb_arn_suffix}/${module.alb.api_target_group_arn_suffix}"

  deployment_minimum_healthy_percent    = local.deployment_minimum_healthy_percent
  deployment_maximum_percent            = local.deployment_maximum_percent
  api_health_check_grace_period_seconds = 60

  container_insights       = "enabled"
  enable_execute_command   = true
  stop_timeout_seconds     = 30
  readonly_root_filesystem = true
  # No writable paths needed: LOG_TO_FILE=false (no ./logs writes) and STORAGE_DRIVER=cloudinary
  # (no ./uploads writes). Add a path here — never disable readonly — if that ever changes.
  writable_container_paths = []

  log_retention_days = 30 # platform-standards.md Section 11: 30 days hot

  permission_boundary_arn = local.network.permission_boundary_arn

  alarm_sns_topic_arn                      = module.alerting.topic_arn
  api_min_running_tasks_alarm_threshold    = local.capacity.api_alarm
  worker_min_running_tasks_alarm_threshold = local.capacity.worker_alarm
}

# The root layer scoped the CI deploy roles to these names before this layer existed — fail loudly
# if the two ever drift apart (the deploy would otherwise hit AccessDenied at release time).
check "ecs_names_match_root_deploy_role_scope" {
  assert {
    condition = (
      module.ecs.cluster_name == local.network.ecs_contract.cluster_name &&
      module.ecs.api_service_name == local.network.ecs_contract.api_service_name &&
      module.ecs.worker_service_name == local.network.ecs_contract.worker_service_name &&
      module.ecs.migration_task_definition_family == local.network.ecs_contract.migration_task_family &&
      module.ecs.migration_log_group_name == local.network.ecs_contract.migration_log_group_name
    )
    error_message = "ECS resource names no longer match the root layer's ecs_contract — the backend deploy role would be denied. Re-align environments/production/main.tf's local.ecs_contract."
  }
}
