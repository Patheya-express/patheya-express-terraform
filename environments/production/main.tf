module "shared" {
  source = "../../modules/shared"

  environment = "production"
  application = "platform"
  purpose     = "Production environment — customer-facing, manual-approval-gated deploys only"
  retention   = "365-days"
}

module "iam" {
  source = "../../modules/iam"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  # Manual-approval-gated (platform-standards.md Section 6) — restricting to `main` (the module
  # default) is necessary but not sufficient on its own; the GitHub Actions workflow's own
  # environment-protection-rule (a manual reviewer gate on the "production" GitHub Environment)
  # is what actually enforces the approval step. That workflow configuration lives in
  # patheya-express-terraform's own .github/workflows/ (added in Phase 7 alongside the rest of
  # CI/CD — explicitly out of scope for this phase, see the root README's "DO NOT IMPLEMENT" list).
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

  vpc_cidr           = "10.30.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs       = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
  private_app_subnet_cidrs  = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
  private_data_subnet_cidrs = ["10.30.64.0/24", "10.30.65.0/24", "10.30.66.0/24"]

  single_nat_gateway = false # one NAT Gateway per AZ — mandatory in production, cloud-architecture-blueprint.md Section 2
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
  flow_log_retention_days = 30

  nlb_allowed_cidrs = var.nlb_allowed_cidrs
}

# No route53 module call here, deliberately: production is the ONE environment that uses the apex
# zone (patheyaexpress.com, environments/shared-services) directly rather than a delegated
# subdomain — platform-standards.md Section 6: "production has no environment prefix." This means
# Phase 3's ExternalDNS (running in this account's EKS cluster) needs cross-account Route53 write
# access into the shared-services account's apex zone — a cross-account IAM role granting exactly
# that, added when ExternalDNS itself is added (Phase 3), not stubbed out here ahead of the
# EKS cluster that would use it.

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

  finding_notification_emails = var.security_finding_notification_emails
}
