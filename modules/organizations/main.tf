# The AWS Organization itself. Terraform creates this FROM the management account — the
# management account's own existence (its root email, initial billing setup) is an unavoidable
# manual prerequisite (see README.md); everything from this resource down is IaC.
resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]

  feature_set = "ALL" # required for SCPs and tag policies — CONSOLIDATED_BILLING alone can't enforce either

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
}

# --- Organizational Units -----------------------------------------------------------------
# Three OUs under the org root, matching cloud-architecture-blueprint.md Section 2's account
# structure: Security (the security/audit account), Infrastructure (shared-services), Workloads
# (development/staging/production/dr — every account that actually runs the platform).

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

locals {
  ou_ids = {
    security       = aws_organizations_organizational_unit.security.id
    infrastructure = aws_organizations_organizational_unit.infrastructure.id
    workloads      = aws_organizations_organizational_unit.workloads.id
  }
}

# --- Member accounts ------------------------------------------------------------------------
resource "aws_organizations_account" "member" {
  for_each = var.member_accounts

  name      = "patheya-${each.key}"
  email     = each.value.email
  parent_id = local.ou_ids[each.value.ou]

  # OrganizationAccountAccessRole is the AWS default — cross-account roles the iam module manages
  # assume THIS role from the management account, never a hand-created one.
  role_name = "OrganizationAccountAccessRole"

  # New member accounts otherwise auto-leave the org's CloudTrail/Config/GuardDuty delegation on
  # account closure by default in some AWS account-creation flows — explicit here so an account
  # removed from this configuration doesn't silently retain org-level service access.
  close_on_deletion = false

  lifecycle {
    # Account email is globally unique and effectively immutable in practice (changing it is an
    # AWS support request, not a Terraform-managed property) — prevents an accidental email typo
    # fix in a PR from being interpreted as "create a new account."
    ignore_changes = [email]
  }

  tags = merge(var.tags, {
    Application = "organizations"
    Purpose     = "member-account-${each.key}"
  })
}
