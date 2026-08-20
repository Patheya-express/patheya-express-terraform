# modules/security

GuardDuty, Security Hub (AWS Foundational Security Best Practices + CIS AWS Foundations Benchmark
v1.4.0 standards), and IAM Access Analyzer — the "Security Baseline" this task's Section 10 asks
for.

## Delegation pattern (same shape as modules/cloudtrail and modules/config)

- **Every account** gets its own GuardDuty detector, Security Hub subscription, and account-level
  Access Analyzer — these three services are inherently per-account even under organization
  management.
- **`environments/management`** calls this module with `delegate_admin_account_id = <security
  account ID>` — designates the security account as the org-wide administrator for GuardDuty and
  Security Hub (only the management account can make this designation).
- **`environments/security`** calls this module with `is_delegated_admin_account = true` — turns on
  organization-wide auto-enrollment (every current and future member account automatically gets
  GuardDuty/Security Hub enabled without a manual per-account opt-in) and creates the
  organization-scoped Access Analyzer.

## Explicitly deferred to Phase 6

Security Hub's full "central configuration" mode (a finding aggregator plus configuration
policies applied org-wide) is enabled here only at the basic level — this task's own "DO NOT
IMPLEMENT" list excludes the deeper security tooling (Kyverno, image signing verification) that a
fuller Security Hub configuration would coordinate with; revisit alongside that Phase 6 work
rather than half-configuring it now.

## Usage

```hcl
# environments/management/main.tf
module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  delegate_admin_account_id = module.organizations.member_account_ids["security"]
}
```

```hcl
# environments/security/main.tf
module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  is_delegated_admin_account = true
  organization_id             = data.terraform_remote_state.management.outputs.organization_id
}
```
