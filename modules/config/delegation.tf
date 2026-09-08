# Phase 0.5 remediation (Organizations trusted-service-access review): AWS Config's organization
# aggregator (aggregator.tf's aws_config_configuration_aggregator.organization) is created from
# environments/security, not the management account. Unlike GuardDuty/SecurityHub — which own a
# dedicated Terraform resource that performs Organizations delegation as part of designating a
# service admin — Config has no such resource; creating an organization_aggregation_source from a
# non-management account requires that account to already be a registered Organizations delegated
# administrator for config.amazonaws.com, or the aggregator's own apply fails.
#
# This resource performs that registration. It must be applied from the management environment —
# RegisterDelegatedAdministrator can only be called by the management account, regardless of which
# account is being registered — even though the file lives in this shared module alongside the
# aggregator it unblocks. environments/security's own module "config" call leaves
# delegate_admin_account_id at its null default; only environments/management passes a real value.
resource "aws_organizations_delegated_administrator" "config" {
  count = var.delegate_admin_account_id != null ? 1 : 0

  account_id        = var.delegate_admin_account_id
  service_principal = "config.amazonaws.com"
}
