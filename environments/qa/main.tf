# Phase 1C.1 — QA root, deliberately scoped to account-level modules only. module.vpc and
# module.networking are intentionally NOT instantiated here yet — every other module below has no
# VPC dependency (only module.networking/module.vpc themselves do), so this is the same modules,
# same calling convention as every other environment's root, just a subset. VPC/networking (and
# the eventual cluster/data/platform layers, mirroring environments/staging's shape) are Phase 1D's
# responsibility once the CIDR/network design for QA is reviewed. Future CIDR: 10.40.0.0/16.

module "shared" {
  source = "../../modules/shared"

  environment = "qa"
  application = "platform"
  purpose     = "QA environment — dedicated quality-assurance workload, isolated from Development"
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
      description         = "Encrypts this account's VPC Flow Logs, Config snapshots, and its security-findings SNS topic"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "config.amazonaws.com", "delivery.logs.amazonaws.com", "sns.amazonaws.com"]
    }
  }
}

module "route53" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "qa.patheyaexpress.com"
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

  finding_notification_emails = var.security_finding_notification_emails
}
