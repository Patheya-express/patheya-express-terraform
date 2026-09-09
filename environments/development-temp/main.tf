# Temporary combined DEV+QA workload — hosted in the Security account (512206886196) while the
# AWS Organizations account quota matures (Phase 1 §3: an approved, explicitly temporary
# compromise, not a pattern to replicate). This root is entirely self-contained: it does not read
# or reference environments/management's or environments/security's state, and composes only the
# application-workload modules approved for this phase — never modules/organizations,
# modules/cloudtrail, modules/config, modules/eks, modules/eks-addons, modules/argocd,
# modules/observability, modules/supply-chain-security, modules/aurora, or modules/route53.
#
# environment = "development" (not "development-temp") is passed to module.shared deliberately —
# this workload IS the future Development workload, just temporarily hosted elsewhere; tags stay
# stable across the eventual account migration (Phase 1 §20). The Terraform ROOT directory name
# carries the "temporary" signal instead.

module "shared" {
  source = "../../modules/shared"

  environment = "development"
  application = "platform"
  purpose     = "Temporary combined DEV+QA workload (ECS Fargate) — hosted in the Security account while the Organizations account quota matures"
  retention   = "30-days"
}

module "vpc" {
  source = "../../modules/vpc"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs

  single_nat_gateway = true # one shared NAT Gateway — the same accepted-for-non-production cost tradeoff environments/development already uses
}

module "networking" {
  source = "../../modules/networking"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  private_data_subnet_ids = module.vpc.private_data_subnet_ids

  flow_log_kms_key_arn    = module.kms.key_arns["database"]
  flow_log_retention_days = 14

  # Still required by the module for the EKS-oriented NLB security group it unconditionally
  # creates for every caller (unmodified, per Phase 2 report §H) — this environment has no NLB and
  # never attaches anything to that security group, but the module's existing validation requires
  # a non-empty list regardless. Reusing the same Cloudflare CIDR list costs nothing.
  nlb_allowed_cidrs = var.cloudflare_ipv4_cidrs

  create_ecs_topology_security_groups = true
  alb_allowed_cidrs                   = var.cloudflare_ipv4_cidrs
  ecs_api_container_port              = 3000
}

module "kms" {
  source = "../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    database = {
      description         = "Encrypts this environment's RDS storage, ElastiCache, Secrets Manager secrets, and CloudWatch Logs — one CMK per data class, per the repository's existing convention (modules/aurora + modules/secrets-manager in every other environment)."
      additional_services = ["secretsmanager.amazonaws.com", "logs.amazonaws.com"]
    }
    ecr = {
      description         = "Encrypts the api-gateway ECR repository — matches environments/shared-services's identical dedicated ECR key."
      additional_services = ["ecr.amazonaws.com"]
    }
  }
}

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "development-temp"
  kms_key_arn = module.kms.key_arns["database"]

  # Matches apps/api-gateway/src/config/env.validation.ts's SECRET-classified external
  # credentials exactly, and reuses the SAME JSON-shape convention Production's own
  # ExternalSecret templates already document (modules/eks-addons/external-secrets.tf's
  # comment) — jwt-signing-key: {accessSecret, refreshSecret}; cloudinary: {cloudName, apiKey,
  # apiSecret}; smtp: {host, port, user, pass, from}. razorpay is extended here with
  # "webhookSecret" alongside the documented {keyId, keySecret} — the application genuinely
  # requires RAZORPAY_WEBHOOK_SECRET (confirmed: modules/payments/providers/razorpay.provider.ts's
  # webhook signature verification) and the existing documented shape was incomplete, not
  # contradicted.
  external_credential_secrets = [
    "jwt-signing-key",
    "cloudinary",
    "razorpay",
    "smtp",
    "bank-account-encryption-key",
    "super-admin-bootstrap",
  ]
}

module "ecr" {
  source = "../../modules/ecr"

  tags            = module.shared.tags
  kms_key_arn     = module.kms.key_arns["ecr"]
  organization_id = var.organization_id

  # Only api-gateway — worker and migration are the same image with a different
  # command/entrypoint (modules/ecr's own existing comment: "do not add a separate worker
  # repository"). No frontend repositories: this root serves the four Angular apps via
  # module.static_site (S3 + CloudFront), not containers.
  repository_names = ["api-gateway"]
}

module "rds" {
  source = "../../modules/rds"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "development-temp"

  vpc_id                  = module.vpc.vpc_id
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  security_group_id       = module.networking.rds_security_group_id
  kms_key_arn             = module.kms.key_arns["database"]

  deletion_protection = false # temporary, intentionally-destroyable environment
}

module "elasticache" {
  source = "../../modules/elasticache"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  redis_security_group_id = module.networking.redis_ecs_security_group_id
  kms_key_arn             = module.kms.key_arns["database"]
  auth_token              = module.secrets_manager.redis_auth_token

  cluster_mode_enabled = false # the application has no Redis.Cluster client anywhere — see Phase 1.5 §1
  num_shards           = 1
  replicas_per_shard   = 0 # DEV+QA target (Phase 1.5): no replica, matching the module's own existing default
  node_type            = "cache.t4g.micro"

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}

# Minimal alarm notification path — deliberately not a full alerting module (Phase 1 §14: "avoid
# unnecessarily reproducing the full EKS observability stack for temporary DEV+QA"). Subscriptions
# only created when var.alert_email_addresses is non-empty.
resource "aws_sns_topic" "alerts" {
  name              = "${module.shared.name_prefix}-alerts"
  kms_master_key_id = module.kms.key_arns["database"]

  tags = merge(module.shared.tags, { Application = "monitoring", Purpose = "temp-devqa-alerts" })
}

resource "aws_sns_topic_subscription" "alerts_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

module "alb" {
  source = "../../modules/alb"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  certificate_arn       = var.alb_certificate_arn
}

locals {
  # Reuses the same JSON-shape convention already documented for Production's ExternalSecret
  # templates (modules/eks-addons/external-secrets.tf) — see module.secrets_manager's comment
  # above for why this is a consistency win, not a divergence.
  external_secret_arns = module.secrets_manager.external_credential_secret_arns

  app_secrets = {
    JWT_ACCESS_SECRET      = "${local.external_secret_arns["jwt-signing-key"]}:accessSecret::"
    JWT_REFRESH_SECRET     = "${local.external_secret_arns["jwt-signing-key"]}:refreshSecret::"
    CLOUDINARY_CLOUD_NAME  = "${local.external_secret_arns["cloudinary"]}:cloudName::"
    CLOUDINARY_API_KEY     = "${local.external_secret_arns["cloudinary"]}:apiKey::"
    CLOUDINARY_API_SECRET  = "${local.external_secret_arns["cloudinary"]}:apiSecret::"
    RAZORPAY_KEY_ID        = "${local.external_secret_arns["razorpay"]}:keyId::"
    RAZORPAY_KEY_SECRET    = "${local.external_secret_arns["razorpay"]}:keySecret::"
    SMTP_HOST              = "${local.external_secret_arns["smtp"]}:host::"
    SMTP_PORT              = "${local.external_secret_arns["smtp"]}:port::"
    SMTP_USER              = "${local.external_secret_arns["smtp"]}:user::"
    SMTP_PASS              = "${local.external_secret_arns["smtp"]}:pass::"
    SMTP_FROM              = "${local.external_secret_arns["smtp"]}:from::"
    SUPER_ADMIN_EMAIL      = "${local.external_secret_arns["super-admin-bootstrap"]}:email::"
    SUPER_ADMIN_PASSWORD   = "${local.external_secret_arns["super-admin-bootstrap"]}:password::"
    SUPER_ADMIN_FIRST_NAME = "${local.external_secret_arns["super-admin-bootstrap"]}:firstName::"
    SUPER_ADMIN_LAST_NAME  = "${local.external_secret_arns["super-admin-bootstrap"]}:lastName::"
    SUPER_ADMIN_PHONE      = "${local.external_secret_arns["super-admin-bootstrap"]}:phone::"
    REDIS_AUTH_TOKEN       = module.secrets_manager.redis_auth_token_secret_arn
  }

  derived_environment = {
    NODE_ENV            = "development"
    PORT                = "3000"
    STORAGE_DRIVER      = "cloudinary"
    LOG_LEVEL           = "info"
    LOG_TO_FILE         = "false"
    SHUTDOWN_TIMEOUT_MS = "10000"
    KAFKA_BROKER        = "localhost:9092" # dead config (no Kafka client exists in the app) — Joi requires the variable to be set to something; matches Render's own identical literal value
    CUSTOMER_APP_URL    = "https://${var.frontend_domains["customer"]}"
    RESTAURANT_APP_URL  = "https://${var.frontend_domains["restaurant"]}"
    ADMIN_APP_URL       = "https://${var.frontend_domains["admin"]}"
    DELIVERY_APP_URL    = "https://${var.frontend_domains["delivery"]}"
    API_PUBLIC_URL      = "https://${var.api_domain}"
    REDIS_HOST          = module.elasticache.primary_endpoint
    REDIS_PORT          = tostring(module.elasticache.port)
    REDIS_TLS           = "true"
  }
}

module "ecs" {
  source = "../../modules/ecs"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "development-temp"

  private_app_subnet_ids     = module.vpc.private_app_subnet_ids
  ecs_task_security_group_id = module.networking.ecs_task_security_group_id
  alb_target_group_arn       = module.alb.target_group_arn

  image_repository_url = module.ecr.repository_urls["api-gateway"]
  image_tag            = var.image_tag

  kms_key_arn             = module.kms.key_arns["database"]
  database_url_secret_arn = module.rds.database_url_secret_arn
  app_secrets             = local.app_secrets
  app_environment         = merge(local.derived_environment, var.app_non_secret_environment)

  permission_boundary_arn = var.permission_boundary_arn
}

module "static_site" {
  source = "../../modules/static-site"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  sites               = var.frontend_domains
  acm_certificate_arn = var.frontend_acm_certificate_arn
  kms_key_arn         = module.kms.key_arns["database"] # frontend build artifacts are not sensitive; reusing this key rather than provisioning a fifth near-identical one is an acceptable simplification (SSE-S3 would also be acceptable — see modules/static-site/variables.tf)
}
