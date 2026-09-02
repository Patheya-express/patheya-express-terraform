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

## Finding notifications

`enable_finding_notifications` (default `true`) creates an SNS topic plus two EventBridge rules —
one for GuardDuty findings at severity >= 4.0 (MEDIUM and above), one for Security Hub findings
labeled HIGH/CRITICAL with workflow status NEW — routing both to that topic. This closes a gap the
Kubernetes-layer tooling (Falco/Kyverno/Trivy, `modules/supply-chain-security`) didn't have: those
already route through Alertmanager, but AWS-native findings had no notification path at all before
this. `finding_notification_emails` (default empty) subscribes real addresses — this repository
doesn't invent one; populate it via the calling environment's tfvars once a real address or
distribution list exists, the same pattern `modules/alerting`'s `email_subscriptions` uses. A
deeper integration (AWS Chatbot into Slack, a PagerDuty AWS integration) would need its own
human-supplied credential and is left for that later, human-approved step — not implemented
speculatively here.

## Usage

```hcl
# environments/management/main.tf
module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  delegate_admin_account_id = module.organizations.member_account_ids["security"]
}
```

```hcl
# environments/security/main.tf
module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  is_delegated_admin_account = true
  organization_id             = data.terraform_remote_state.management.outputs.organization_id
}
```
