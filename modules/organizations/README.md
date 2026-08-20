# modules/organizations

AWS Organizations: the org itself, three OUs (Security, Infrastructure, Workloads), the six member
accounts from `cloud-architecture-blueprint.md` Section 2, baseline Service Control Policies,
per-account AWS Budgets, and (gated, optional) IAM Identity Center permission sets/assignments.

**Not an explicit module in the task's requested `modules/` list** — added because Section 2's
requirements (Organization, Accounts, SCPs, Billing, IAM Identity Center) have no other home in
that list. Called out here and in the repository's top-level README rather than silently folded
into `modules/iam` or `modules/security`.

## Manual prerequisites (cannot be created by Terraform)

1. **The management account itself.** AWS Organizations is created *from* an already-existing AWS
   account with valid billing set up — that account's creation (root email, payment method) is
   outside Terraform's reach by construction. This module's `aws_organizations_organization`
   resource is what turns that already-existing account into an organization's management account.
2. **IAM Identity Center's instance.** Must be manually enabled once (Console: IAM Identity Center
   → Enable, or `aws sso-admin` — there is no `aws_ssoadmin_instance` create resource in the AWS
   provider). Until that's done, leave `enable_identity_center = false` (the default) — every
   resource in `identity-center.tf` is gated behind that variable and simply doesn't get created
   otherwise, so a fresh `apply` never fails looking for a missing instance.
3. **Identity Store groups.** After enabling Identity Center, create the four groups
   (`platform-administrator`, `developer`, `read-only`, `security-auditor`) and populate
   `var.identity_center_group_ids` with their resulting Group IDs before setting
   `enable_identity_center = true`.

## Usage

See `environments/management/main.tf` for the actual call — this module is deployed exactly once,
against the management account, never per-environment.

## Outputs consumed elsewhere

`member_account_ids` feeds every other environment's `provider "aws" { assume_role { role_arn = ...
} }` block (`environments/{development,staging,production}/versions.tf`) and `modules/iam`'s
cross-account trust policies.
