# Phase 1D.2 — network layer, split out of the account root (../main.tf) so that VPC/networking
# changes plan and apply independently of IAM/Route53/Config/Security/GuardDuty/SecurityHub, and
# vice versa (Phase 1D.1's approved design). Owns module.vpc, module.networking, and the single
# KMS key VPC Flow Logs genuinely requires ("cloudtrail-logs") — this is the same key the account
# root's module.config and module.security also need; they read it from this root's own state
# (see outputs.tf) rather than each creating their own, so there is exactly one such key, owned in
# exactly one place.

module "shared" {
  source = "../../../modules/shared"

  environment = "development"
  application = "network"
  purpose     = "Development VPC, subnets, networking security groups, and VPC Flow Logs"
  retention   = "n/a"
}

module "kms" {
  source = "../../../modules/kms"

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
  source = "../../../modules/vpc"

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
  source = "../../../modules/networking"

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
