# IAM Identity Center (AWS SSO) — the instance itself is NOT created here. It has no Terraform
# resource because AWS requires it to be manually enabled once, per organization, via the Console
# or `aws sso-admin` CLI (see README.md's manual-prerequisite note). Everything below only runs
# when var.enable_identity_center = true, i.e. after that one manual step is done — a fresh
# `terraform apply` of this module against a brand-new org never fails looking for an instance
# that doesn't exist yet.

data "aws_ssoadmin_instances" "this" {
  count = var.enable_identity_center ? 1 : 0
}

locals {
  sso_instance_arn  = var.enable_identity_center ? data.aws_ssoadmin_instances.this[0].arns[0] : null
  identity_store_id = var.enable_identity_center ? data.aws_ssoadmin_instances.this[0].identity_store_ids[0] : null
}

# --- Permission sets --------------------------------------------------------------------------
# Four roles, matching the four groups platform-standards.md's least-privilege posture implies —
# no fifth "just in case" permission set; a new role needs an ADR (platform-standards.md Section 23)
# the same as any other cross-cutting security change.

resource "aws_ssoadmin_permission_set" "platform_administrator" {
  count = var.enable_identity_center ? 1 : 0

  name             = "PlatformAdministrator"
  description      = "Full account administration — platform engineering only."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
  tags             = merge(var.tags, { Application = "organizations", Purpose = "sso-platform-administrator" })
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_administrator" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_administrator[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_permission_set" "developer" {
  count = var.enable_identity_center ? 1 : 0

  name             = "Developer"
  description      = "Broad service access for day-to-day work, explicitly excluding IAM/Organizations changes."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  tags             = merge(var.tags, { Application = "organizations", Purpose = "sso-developer" })
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_power_user" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "developer_deny_iam_org" {
  statement {
    sid    = "DenyIAMAndOrganizationsChanges"
    effect = "Deny"
    actions = [
      "iam:*",
      "organizations:*",
    ]
    resources = ["*"]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "developer_deny_iam_org" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer[0].arn
  inline_policy      = data.aws_iam_policy_document.developer_deny_iam_org.json
}

resource "aws_ssoadmin_permission_set" "read_only" {
  count = var.enable_identity_center ? 1 : 0

  name             = "ReadOnly"
  description      = "Read-only access across every service — the default for anyone who needs visibility without change authority."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  tags             = merge(var.tags, { Application = "organizations", Purpose = "sso-read-only" })
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssoadmin_permission_set" "security_auditor" {
  count = var.enable_identity_center ? 1 : 0

  name             = "SecurityAuditor"
  description      = "AWS-managed SecurityAudit policy — read access to security/config-relevant resources across every account, for the security team."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  tags             = merge(var.tags, { Application = "organizations", Purpose = "sso-security-auditor" })
}

resource "aws_ssoadmin_managed_policy_attachment" "security_auditor" {
  count              = var.enable_identity_center ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.security_auditor[0].arn
  managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

# --- Account assignments ----------------------------------------------------------------------
# PlatformAdministrator + SecurityAuditor: every account, including management — platform
# engineering and security both need cross-account visibility/administration by design.
# Developer: workloads accounts only (development, staging, production) — never security,
# shared-services, or dr. ReadOnly: every account — the safe default assignment.

locals {
  all_account_ids = var.enable_identity_center ? merge(
    { management = data.aws_caller_identity.current[0].account_id },
    { for k, v in aws_organizations_account.member : k => v.id }
  ) : {}

  developer_account_ids = var.enable_identity_center ? {
    for k, v in aws_organizations_account.member : k => v.id
    if contains(["development", "staging", "production"], k)
  } : {}
}

data "aws_caller_identity" "current" {
  count = var.enable_identity_center ? 1 : 0
}

resource "aws_ssoadmin_account_assignment" "platform_administrator" {
  for_each = var.enable_identity_center ? local.all_account_ids : {}

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_administrator[0].arn
  principal_id       = var.identity_center_group_ids["platform-administrator"]
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "security_auditor" {
  for_each = var.enable_identity_center ? local.all_account_ids : {}

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.security_auditor[0].arn
  principal_id       = var.identity_center_group_ids["security-auditor"]
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "read_only" {
  for_each = var.enable_identity_center ? local.all_account_ids : {}

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only[0].arn
  principal_id       = var.identity_center_group_ids["read-only"]
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "developer" {
  for_each = local.developer_account_ids

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer[0].arn
  principal_id       = var.identity_center_group_ids["developer"]
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

# --- DevQAWorkloadOperator (Phase 2, temporary DEV+QA) ------------------------------------------
# A fifth, deliberately narrow permission set — NOT an extension of Developer's assignment model
# above (which is, and remains, workloads-accounts-only) and NOT an SCP (an SCP would apply
# account-wide and cannot distinguish "the DevQA operator" from the security team's own
# legitimate GuardDuty/SecurityHub/Config/CloudTrail/Access-Analyzer administration happening in
# the same account). This permission set exists solely because environments/development-temp's
# compute has been placed in the Security account as an approved, explicitly-temporary compromise
# (Phase 1 §3) — it must never be assigned anywhere else, and must never be able to touch this
# account's actual security-tooling administration.
#
# Disabled by default (var.enable_devqa_temp_operator_permission_set = false) — a plain
# terraform apply of this module, with no new variables set, creates nothing here, exactly like
# every other resource in this file gated behind var.enable_identity_center.

resource "aws_ssoadmin_permission_set" "devqa_workload_operator" {
  count = var.enable_identity_center && var.enable_devqa_temp_operator_permission_set ? 1 : 0

  name             = "DevQAWorkloadOperator"
  description      = "Operates the temporary DEV+QA ECS/RDS/ElastiCache/ALB workload in the Security account only — explicitly denied any CloudTrail/GuardDuty/SecurityHub/Config/Access-Analyzer/IAM/Organizations administration."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
  tags             = merge(var.tags, { Application = "organizations", Purpose = "sso-devqa-workload-operator" })
}

data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "devqa_workload_operator" {
  count = var.enable_identity_center && var.enable_devqa_temp_operator_permission_set ? 1 : 0

  # Narrow, workload-oriented allow-list — only the services environments/development-temp's own
  # modules (ecs, alb, rds, elasticache, ecr) actually provision. Not PowerUserAccess: this
  # permission set exists in an account it should have as little standing reach in as possible.
  statement {
    sid    = "AllowDevQAWorkloadServices"
    effect = "Allow"
    actions = [
      "ecs:*",
      "elasticloadbalancing:*",
      "rds:*",
      "elasticache:*",
      "logs:*",
      "cloudwatch:*",
      "ecr:*",
    ]
    resources = ["*"]
  }

  # Secrets Manager access resource-scoped to this workload's own path prefix only — never a
  # blanket secretsmanager:* on "*", since the Security account may hold other, unrelated secrets
  # (e.g. environments/security's own, once applied).
  statement {
    sid    = "AllowDevQAWorkloadSecretsOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current[0].account_id}:secret:patheya-express/development-temp/*",
    ]
  }

  # Explicit deny — the entire point of this permission set. Follows the exact same
  # inline-deny-policy pattern already used by the Developer permission set above
  # (aws_ssoadmin_permission_set_inline_policy + a Deny statement), extended with the five
  # security-administration services this account uniquely hosts.
  statement {
    sid    = "DenySecurityAdministrationAndIAMOrg"
    effect = "Deny"
    actions = [
      "iam:*",
      "organizations:*",
      "cloudtrail:*",
      "guardduty:*",
      "securityhub:*",
      "config:*",
      "access-analyzer:*",
    ]
    resources = ["*"]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "devqa_workload_operator" {
  count              = var.enable_identity_center && var.enable_devqa_temp_operator_permission_set ? 1 : 0
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devqa_workload_operator[0].arn
  inline_policy      = data.aws_iam_policy_document.devqa_workload_operator[0].json
}

# Assigned to the Security account ONLY — never Management, never any workloads account, and
# never merged into local.all_account_ids/local.developer_account_ids above. If the "security"
# key is not yet present in aws_organizations_account.member (e.g. this module applied before
# that account existed), this for_each is simply empty — it does not error, and does not assign
# anything prematurely.
resource "aws_ssoadmin_account_assignment" "devqa_workload_operator" {
  for_each = var.enable_identity_center && var.enable_devqa_temp_operator_permission_set ? (
    contains(keys(aws_organizations_account.member), "security") ? { security = aws_organizations_account.member["security"].id } : {}
  ) : {}

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devqa_workload_operator[0].arn
  principal_id       = var.identity_center_group_ids["devqa-workload-operator"]
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}
