# No resources — this module is pure computed output, consumed by every other module so the
# mandatory tag set (platform-standards.md Section 5) and naming prefix (Section 4) are defined
# exactly once, not re-derived per module with the risk of drifting.

locals {
  # patheya-<environment> — the base every Section 4 AWS-resource naming pattern builds on
  # (patheya-<env>-vpc, patheya-<env>-aurora, ...). "management" has no further env-scoping since
  # it's a singleton account, not one of the dev/staging/prod triad.
  name_prefix = "patheya-${var.environment}"

  # All fourteen mandatory tags (platform-standards.md Section 5) — a module that forgets to
  # merge var.tags_extra in still produces a fully tag-compliant resource; the extra map only adds,
  # never substitutes for, one of these fourteen.
  tags = merge(
    {
      Environment     = var.environment
      Project         = "patheya-express"
      Owner           = var.owner
      ManagedBy       = "terraform"
      CostCenter      = var.cost_center
      Repository      = var.repository
      Application     = var.application
      Version         = var.resource_version
      Confidentiality = var.confidentiality
      BusinessUnit    = var.business_unit
      Compliance      = var.compliance
      Retention       = var.retention
      CreatedBy       = "terraform-ci"
      Purpose         = var.purpose
    },
    var.tags_extra
  )
}
