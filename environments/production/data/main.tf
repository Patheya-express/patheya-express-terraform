data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-<production-account-id>"
    key    = "production/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "production"
  application = "data-platform"
  purpose     = "Production Aurora PostgreSQL, ElastiCache Redis, and Secrets Manager"
  retention   = "35-days"
}

module "kms" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    aurora = {
      description         = "Encrypts the Aurora PostgreSQL cluster, its RDS-managed master secret, and Performance Insights"
      key_administrators  = [data.terraform_remote_state.network.outputs.terraform_role_arn]
      additional_services = ["rds.amazonaws.com"]
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

  external_credential_secrets = ["jwt-signing-key", "cloudinary", "razorpay", "smtp"]
}

module "aurora" {
  source = "../../../modules/aurora"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "production"

  vpc_id                   = data.terraform_remote_state.network.outputs.vpc_id
  private_data_subnet_ids  = data.terraform_remote_state.network.outputs.private_data_subnet_ids
  aurora_security_group_id = data.terraform_remote_state.network.outputs.aurora_security_group_id
  kms_key_arn              = module.kms.key_arns["aurora"]

  serverless            = false # provisioned db.r6g instances (cloud-architecture-blueprint.md Section 5's production row)
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

  node_type          = "cache.r6g.large"
  num_shards         = 3
  replicas_per_shard = 1 # "3 shards, each 1 primary + 1 replica, Multi-AZ automatic failover" (cloud-architecture-blueprint.md Section 6)

  snapshot_retention_days = 7
  apply_immediately       = false

  alarm_sns_topic_arn = module.alerting.topic_arn
}
