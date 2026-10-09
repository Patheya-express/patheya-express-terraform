data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "production"
  application = "data-platform"
  purpose     = "Production Aurora PostgreSQL, RDS Proxy, ElastiCache Redis, and Secrets Manager"
  retention   = "35-days"
}

module "kms" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    aurora = {
      description        = "Encrypts the Aurora PostgreSQL cluster, its RDS-managed master secret, and Performance Insights"
      key_administrators = [data.terraform_remote_state.network.outputs.terraform_role_arn]
      # cloudwatch.amazonaws.com: CloudWatch alarms publish to the alerts-database SNS topic, which
      # this key encrypts (module.alerting) — without it every encrypted alarm notification fails.
      additional_services = ["rds.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
    redis = {
      description         = "Encrypts the ElastiCache Redis replication group at rest"
      key_administrators  = [data.terraform_remote_state.network.outputs.terraform_role_arn]
      additional_services = ["elasticache.amazonaws.com"]
    }
    secrets = {
      description         = "Encrypts Secrets Manager entries this environment owns (Redis AUTH token, external SaaS credential containers)"
      key_administrators  = [data.terraform_remote_state.network.outputs.terraform_role_arn]
      additional_services = ["secretsmanager.amazonaws.com"]
    }
  }
}

module "kms_dr" {
  source    = "../../../modules/kms"
  providers = { aws = aws.dr }

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    aurora-backup-dr = {
      description         = "Encrypts the DR-region (ap-southeast-1) copy of Aurora's AWS Backup snapshots"
      key_administrators  = [data.terraform_remote_state.network.outputs.terraform_role_arn]
      additional_services = ["backup.amazonaws.com"]
    }
  }
}

module "aurora_backup_vault_dr" {
  source    = "../../../modules/backup-vault"
  providers = { aws = aws.dr }

  tags        = module.shared.tags
  name        = "${module.shared.name_prefix}-aurora-vault-dr"
  kms_key_arn = module.kms_dr.key_arns["aurora-backup-dr"]
}

module "alerting" {
  source = "../../../modules/alerting"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["aurora"]
  topic_name  = "alerts-database"

  email_subscriptions = var.alert_email_subscriptions
}

module "secrets_manager" {
  source = "../../../modules/secrets-manager"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "production"
  kms_key_arn = module.kms.key_arns["secrets"]

  # Empty containers, populated out-of-band (docs/production-database-bootstrap.md lists each
  # secret's JSON shape — the same shapes development-temp's ECS wiring already uses):
  #   jwt-signing-key             {accessSecret, refreshSecret}
  #   cloudinary                  {cloudName, apiKey, apiSecret}
  #   razorpay                    {keyId (rzp_live_...), keySecret, webhookSecret}
  #   smtp                        {host, port, user, pass, from}
  #   bank-account-encryption-key plain string — BANK_ACCOUNT_ENCRYPTION_KEY, required at boot
  #   super-admin-bootstrap       {email, password, firstName, lastName, phone}
  external_credential_secrets = [
    "jwt-signing-key",
    "cloudinary",
    "razorpay",
    "smtp",
    "bank-account-encryption-key",
    "super-admin-bootstrap",
  ]
}

module "aurora" {
  source = "../../../modules/aurora"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "production"

  vpc_id                   = data.terraform_remote_state.network.outputs.vpc_id
  private_data_subnet_ids  = data.terraform_remote_state.network.outputs.private_data_subnet_ids
  aurora_security_group_id = local.aurora_cluster_security_group_id # carries the RDS service-linked-role ordering (database-access.tf)
  kms_key_arn              = module.kms.key_arns["aurora"]

  engine_version        = "16.15" # PostgreSQL 16 (aurora-postgresql16 family); the module default 16.4 is no longer offered in ap-south-1
  serverless            = false   # provisioned db.r6g instances (cloud-architecture-blueprint.md Section 5's production row)
  instance_class_writer = "db.r6g.xlarge"
  instance_class_reader = "db.r6g.large"
  reader_count          = 2 # "1 writer + 2 readers, one per AZ"
  deletion_protection   = true
  apply_immediately     = false

  backup_retention_days               = 35  # Aurora's maximum, production only
  performance_insights_retention_days = 731 # paid tier — real incident-postmortem lookback
  monitoring_interval_seconds         = 15  # finest Enhanced Monitoring granularity

  alarm_sns_topic_arn = module.alerting.topic_arn
  dr_backup_vault_arn = module.aurora_backup_vault_dr.arn
}

module "elasticache" {
  source = "../../../modules/elasticache"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = data.terraform_remote_state.network.outputs.vpc_id
  private_data_subnet_ids = data.terraform_remote_state.network.outputs.private_data_subnet_ids
  redis_security_group_id = data.terraform_remote_state.network.outputs.redis_security_group_id
  kms_key_arn             = module.kms.key_arns["redis"]
  auth_token              = module.secrets_manager.redis_auth_token

  # Cluster mode DISABLED: the application's ioredis client (and therefore BullMQ and the Socket.IO
  # Redis adapter) is not cluster-aware — apps/api-gateway/src/infrastructure/redis. One primary +
  # one replica, Multi-AZ automatic failover; the client reconnects on READONLY during promotion.
  # TLS in transit and the AUTH token are always on (modules/elasticache).
  node_type            = "cache.r6g.large"
  cluster_mode_enabled = false
  replicas_per_shard   = 1

  snapshot_retention_days = 7
  apply_immediately       = false

  alarm_sns_topic_arn = module.alerting.topic_arn
}
