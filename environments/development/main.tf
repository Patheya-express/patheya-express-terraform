module "shared" {
  source = "../../modules/shared"

  environment = "development"
  application = "platform"
  purpose     = "Development environment — continuous deploy on every merge to main"
  retention   = "7-days"
}

module "iam" {
  source = "../../modules/iam"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
}

module "kms" {
  source = "../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    cloudtrail-logs = {
      description         = "Encrypts this account's VPC Flow Logs, Config snapshots, and its security-findings SNS topic"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "config.amazonaws.com", "delivery.logs.amazonaws.com", "sns.amazonaws.com"]
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_cidr           = "10.10.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs       = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  private_app_subnet_cidrs  = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
  private_data_subnet_cidrs = ["10.10.64.0/24", "10.10.65.0/24", "10.10.66.0/24"]

  single_nat_gateway = true # cost tradeoff acceptable in development only — see modules/vpc's variable description
}

module "networking" {
  source = "../../modules/networking"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  private_data_subnet_ids = module.vpc.private_data_subnet_ids

  flow_log_kms_key_arn    = module.kms.key_arns["cloudtrail-logs"]
  flow_log_retention_days = 7 # matches development's shorter log retention (platform-standards.md Section 11)

  nlb_allowed_cidrs = var.nlb_allowed_cidrs
}

module "route53" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "dev.patheyaexpress.com"
}

module "config" {
  source = "../../modules/config"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]
}

module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]
  # is_delegated_admin_account and delegate_admin_account_id both left at their false/null
  # defaults — this account is enrolled automatically by the security account's org-wide
  # auto-enable (modules/security's guardduty.tf / security-hub.tf), it doesn't configure
  # delegation itself.

  finding_notification_emails = var.security_finding_notification_emails
}
