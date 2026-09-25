module "shared" {
  source = "../../modules/shared"

  environment = "management"
  application = "platform"
  purpose     = "Management account — AWS Organizations, IAM Identity Center, org-wide CI/CD identity"
  retention   = "n/a"
}

module "organizations" {
  source = "../../modules/organizations"

  tags = module.shared.tags

  management_account_email   = var.management_account_email
  member_accounts            = var.member_accounts
  budget_notification_emails = var.budget_notification_emails

  enable_identity_center    = var.enable_identity_center
  identity_center_group_ids = var.identity_center_group_ids

  platform_administrator_account_keys = var.platform_administrator_account_keys
  read_only_account_keys              = var.read_only_account_keys
  security_auditor_account_keys       = var.security_auditor_account_keys
  developer_account_keys              = var.developer_account_keys

  # Phase 2 (temporary DEV+QA on ECS Fargate in the Security account) — false by default, so this
  # existing management plan is completely unaffected unless explicitly turned on. See
  # modules/organizations/identity-center.tf's DevQAWorkloadOperator resources.
  enable_devqa_temp_operator_permission_set = var.enable_devqa_temp_operator_permission_set
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
      description         = "Encrypts the organization CloudTrail's CloudWatch Logs feed in this account, and this account's security-findings SNS topic"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "sns.amazonaws.com"]
    }
  }
}

# GuardDuty/Security Hub enabled locally for this account too (every account gets its own
# detector — modules/security's README explains why), plus the org-wide delegation to the
# security account, which only the management account can perform.
module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  delegate_admin_account_id   = var.security_account_id
  finding_notification_emails = var.security_finding_notification_emails
}

# This account owns the trail resource (org trails can only be created here); the destination
# bucket lives in environments/security — see variables.tf's note on the two-pass apply this requires.
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  tags        = module.shared.tags
  name_prefix = "patheya-express" # org-wide resource, not per-environment scoped

  create_destination_bucket = false
  create_trail              = true
  existing_bucket_name      = var.security_account_cloudtrail_bucket_name
  kms_key_arn               = module.kms.key_arns["cloudtrail-logs"]
}

module "config" {
  source = "../../modules/config"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  # Registers the security account as Config's delegated administrator — only the management
  # account can perform this — unblocking environments/security's organization aggregator.
  # See modules/config/delegation.tf.
  delegate_admin_account_id = var.security_account_id
}
