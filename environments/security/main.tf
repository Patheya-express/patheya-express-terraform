module "shared" {
  source = "../../modules/shared"

  environment = "security"
  application = "platform"
  purpose     = "Security/audit account — CloudTrail log archive, GuardDuty/Security Hub delegated administration, org-wide Access Analyzer"
  retention   = "indefinite"
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
      description         = "Encrypts the organization CloudTrail log archive, this account's own Config snapshots, and its security-findings SNS topic"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "config.amazonaws.com", "sns.amazonaws.com"]
      key_administrators  = [module.iam.terraform_role_arn]
    }
  }
}

module "cloudtrail" {
  source = "../../modules/cloudtrail"

  tags        = module.shared.tags
  name_prefix = "patheya-express"

  create_destination_bucket = true
  create_trail              = false
  organization_id           = var.organization_id
  management_account_id     = var.management_account_id
  kms_key_arn               = module.kms.key_arns["cloudtrail-logs"]
}

module "config" {
  source = "../../modules/config"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  create_aggregator = true
  organization_id   = var.organization_id
}

module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  is_delegated_admin_account  = true
  organization_id             = var.organization_id
  finding_notification_emails = var.security_finding_notification_emails
}
