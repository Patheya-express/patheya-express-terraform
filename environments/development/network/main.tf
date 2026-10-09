# Phase 1D.2 — network layer, split out of the account root (../main.tf) so that VPC/networking
# changes plan and apply independently of IAM/Route53/Config/Security/GuardDuty/SecurityHub, and
# vice versa (Phase 1D.1's approved design). Owns module.vpc and module.networking.
#
# The "cloudtrail-logs" KMS key VPC Flow Logs need is NOT owned here - it moved to the account
# root (../main.tf) so module.config/module.security can consume it directly, same-root, instead
# of a cross-state read. This root now reads it back via the data source below - the reverse of
# the direction that key's ownership used to imply. There is still exactly one such key.

data "aws_kms_alias" "cloudtrail_logs" {
  name = "alias/patheya-development-cloudtrail-logs"
}

module "shared" {
  source = "../../../modules/shared"

  environment = "development"
  application = "network"
  purpose     = "Development VPC, subnets, networking security groups, and VPC Flow Logs"
  retention   = "n/a"
}

# Development workload networking is intentionally deferred — Development's application
# workload runs on external platforms (Render/Neon/Upstash/Vercel), not AWS, so this VPC has
# no consumer today. module.vpc/module.networking are gated off by default (0 resources) rather
# than deleted, so the design (CIDRs, AZ selection, NAT/flow-log/security-group configuration)
# stays intact for reactivation: set enable_development_network = true to bring it back exactly
# as designed. ../cluster, ../data, and ../platform consume this root's outputs but are
# themselves unapplied scaffolding for the same deferred workload — they need their own
# follow-up (tfvars, etc.) before being ready, independent of this flag.
module "vpc" {
  source = "../../../modules/vpc"

  count = var.enable_development_network ? 1 : 0

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

  count = var.enable_development_network ? 1 : 0

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc[0].vpc_id
  vpc_cidr                = module.vpc[0].vpc_cidr
  private_data_subnet_ids = module.vpc[0].private_data_subnet_ids

  flow_log_kms_key_arn    = data.aws_kms_alias.cloudtrail_logs.target_key_arn
  flow_log_retention_days = 7 # matches development's shorter log retention (platform-standards.md Section 11)

  nlb_allowed_cidrs = var.nlb_allowed_cidrs
}
