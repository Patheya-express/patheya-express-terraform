# Phase 1D.2 — account/baseline layer. module.vpc/module.networking and the "cloudtrail-logs"
# module.kms call moved to environments/development/network/ (own state,
# development/network/terraform.tfstate) so a routine networking change never has to plan
# alongside IAM/Route53/Config/Security/GuardDuty/SecurityHub, and vice versa (Phase 1D.1's
# approved design). This root keeps its original state key — nothing here needed a new one, only
# fewer resources in it. module.config/module.security's kms_key_arn now comes from the network
# layer's own state instead of a local module.kms call; the key itself is unchanged, still exactly
# one, still owned in exactly one place (network/).

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-433985779683"
    key    = "development/network/terraform.tfstate"
    region = "ap-south-1"
  }
}

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

# No route53 module: the dev.patheyaexpress.com zone, its ACM certificate and validation record
# were deleted on 2026-10-03 (approved development-temp/Development cleanup) — Development is not
# AWS-hosted. The next plan of this root refreshes the three deleted resources out of state; it must
# not recreate them.

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
