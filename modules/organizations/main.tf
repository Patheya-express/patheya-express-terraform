# The AWS Organization itself. Terraform creates this FROM the management account — the
# management account's own existence (its root email, initial billing setup) is an unavoidable
# manual prerequisite (see README.md); everything from this resource down is IaC.
resource "aws_organizations_organization" "this" {
  # Phase 0.5 remediation (Organizations trusted-service-access review, verified against live
  # AWS discovery): every principal here is required by a resource that actually exists in this
  # repository — see the citations below. tagpolicies.tag.amazonaws.com was removed: this
  # repository defines zero aws_organizations_policy resources of type TAG_POLICY anywhere, so
  # that principal (and the TAG_POLICY entry in enabled_policy_types, below) enabled a capability
  # with no consumer — the opposite of this codebase's own stated "not created idle ahead of
  # need" principle. access-analyzer.amazonaws.com was added: modules/security's
  # aws_accessanalyzer_analyzer.organization (type = "ORGANIZATION") requires the calling account
  # to be a registered delegated administrator, which in turn requires this service to already be
  # trusted — this principal was previously missing entirely.
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",      # modules/cloudtrail's is_organization_trail = true (management account only)
    "config.amazonaws.com",          # modules/config's organization aggregator + its new delegated-admin registration (modules/config/delegation.tf)
    "guardduty.amazonaws.com",       # modules/security's aws_guardduty_organization_admin_account
    "securityhub.amazonaws.com",     # modules/security's aws_securityhub_organization_admin_account
    "sso.amazonaws.com",             # modules/organizations/identity-center.tf — already the sole principal enabled in the live organization
    "access-analyzer.amazonaws.com", # modules/security's aws_accessanalyzer_analyzer.organization + its new delegated-admin registration
  ]

  feature_set = "ALL" # required for SCPs — CONSOLIDATED_BILLING alone can't enforce them; matches the live organization's FeatureSet exactly

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    # TAG_POLICY deliberately not enabled — no aws_organizations_policy of that type exists
    # anywhere in this repository; matches the live organization's current state exactly.
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
