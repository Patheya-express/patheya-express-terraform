module "shared" {
  source = "../../modules/shared"

  environment = "staging"
  application = "platform"
  purpose     = "Staging environment — pre-production validation, DR drill target"
  retention   = "30-days"
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
      description         = "Encrypts this account's VPC Flow Logs and Config snapshots"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "config.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs       = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_app_subnet_cidrs  = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
  private_data_subnet_cidrs = ["10.20.64.0/24", "10.20.65.0/24", "10.20.66.0/24"]

  single_nat_gateway = false # staging mirrors production's topology at lower scale (cloud-architecture-blueprint.md Section 4) — one NAT per AZ, not the dev cost-shortcut
}

module "networking" {
  source = "../../modules/networking"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  private_data_subnet_ids = module.vpc.private_data_subnet_ids

  flow_log_kms_key_arn = module.kms.key_arns["cloudtrail-logs"]
}

module "route53" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "staging.patheyaexpress.com"
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
}
