# Bootstrap guide — deployment order

This is the one document that must be followed in order. Every step depends on the previous one's
output. Steps marked **(manual)** cannot be done by Terraform — see each module's own README for
why.

## 0. Prerequisites (manual)

1. A single AWS account already exists with billing configured — this becomes the management
   account. Its creation is outside Terraform's reach by construction (`modules/organizations`
   README).
2. Someone with root/administrator access to that account can run Terraform locally (not yet via
   CI — the GitHub OIDC roles this repository creates don't exist until later steps).
3. `terraform` (`= 1.9.8`) and `aws` CLI v2 installed locally.
4. Seven email addresses ready for the seven AWS accounts (`aws-root@`, `aws-security@`,
   `aws-shared-services@`, `aws-development@`, `aws-staging@`, `aws-production@`, `aws-dr@`,
   or your own naming — each must be globally unique across all of AWS, never reused).

## 1. Bootstrap the management account's state backend (manual, local)

```bash
cd bootstrap
terraform init
terraform apply -var="account_alias=management" -var="account_id=<management-account-id>"
```

Follow `bootstrap/README.md`'s state-migration step afterward.

## 2. Deploy `environments/management`

```bash
cd environments/management
cp terraform.tfvars.example terraform.tfvars   # fill in real values
# Edit backend.tf: replace <management-account-id> with the real ID
terraform init
terraform plan
terraform apply
```

This creates the AWS Organization, the three OUs, and the five member accounts this phase actually
provisions (`security`, `shared-services`, `development`, `staging`, `production`). **`dr` is
deferred and must not appear in `member_accounts` for this pass** — it's built alongside Phase
3/4's EKS/data-layer work, not ahead of having anything to protect (see the root README's Scope
section). Note the `member_account_ids` output — you'll need each account's ID in every following
step.

**This is the first of a four-stage sequence, not a single pass**, because the `security` module's
`delegate_admin_account_id`, the `config` module's `delegate_admin_account_id`, and the
`cloudtrail` module's `existing_bucket_name` all reference the security account's own identity or
resources, which don't exist yet:

1. **Management Pass 1** (this step): set `security_account_id = null` and
   `security_account_cloudtrail_bucket_name = null` in `terraform.tfvars`. Both are `!= null`-gated
   (or, for CloudTrail's organization trail, gated on `existing_bucket_name != null` alongside
   `create_trail`), so the `aws_guardduty_organization_admin_account` /
   `aws_securityhub_organization_admin_account` / `aws_organizations_delegated_administrator`
   (Config, and — inside the `security` module — Access Analyzer) / `aws_cloudtrail` resources are
   cleanly **omitted from the plan**, not planned-and-expected-to-fail. Everything else in this
   environment (the organization, the accounts, IAM, KMS, the rest of Config) applies normally.
2. **Security Pass 1** (Step 4, below): creates the security account's own infrastructure,
   including the CloudTrail destination bucket — the one resource in that pass with no dependency
   on management having delegated anything yet.
3. **Management Pass 2**: re-apply this same environment with the real `security_account_id` (from
   Pass 1's `member_account_ids` output) and the real `security_account_cloudtrail_bucket_name`
   (from Security Pass 1's `cloudtrail_bucket_name` output) — now non-null, so all five previously
   -omitted resources are created for real.
4. **Security Pass 2**: re-apply `environments/security` — its organization aggregator, org-wide
   Access Analyzer, GuardDuty org-configuration, and Security Hub CENTRAL config were not creatable
   during Security Pass 1 (they all depend on Management Pass 2's delegated-administrator
   registrations succeeding first) and only become applyable now.

## 3. Bootstrap every member account's state backend (manual, local, once per account)

For each of `security`, `shared-services`, `development`, `staging`, `production` (skip `dr` for
now — it's out of scope for this phase, see the root README):

1. Assume `OrganizationAccountAccessRole` into that account (AWS CLI:
   `aws sts assume-role --role-arn arn:aws:iam::<account-id>:role/OrganizationAccountAccessRole
   --role-session-name bootstrap`, export the resulting credentials).
2. Run the same `bootstrap/` procedure as Step 1, with that account's alias and ID.

## 4. Deploy `environments/security`

```bash
cd environments/security
cp terraform.tfvars.example terraform.tfvars   # organization_id from Step 2's output, management_account_id from Step 0
# Edit backend.tf with the real account ID
terraform init && terraform plan && terraform apply
```

Still using the assumed `OrganizationAccountAccessRole` session from Step 3 (this account's own
GitHub OIDC Terraform role doesn't exist as a usable CI identity until Step 4's `iam` module
applies **and** a GitHub Actions workflow is configured to use it — Phase 7).

Note the `cloudtrail_bucket_name` output. **Go back to Step 2** and re-apply `environments/management`
with the real `security_account_id` and `security_account_cloudtrail_bucket_name` values.

## 5. Deploy `environments/shared-services`

```bash
cd environments/shared-services
cp terraform.tfvars.example terraform.tfvars   # organization_id from Step 2; leave the two *_zone_name_servers as [] for now
terraform init && terraform plan && terraform apply
```

Note the `apex_zone_name_servers` output — give these to your domain registrar for
`patheyaexpress.com` (a manual, one-time action at your registrar, not a Terraform step).

## 6. Deploy `environments/development` and `environments/staging`

```bash
cd environments/development   # then repeat for staging
terraform init && terraform plan && terraform apply
```

Note each one's `route53_name_servers` output.

## 7. Wire up Route53 delegation

Go back to `environments/shared-services`, fill in the real `development_zone_name_servers` and
`staging_zone_name_servers` values from Step 6, and re-apply.

## 8. Deploy `environments/production`

```bash
cd environments/production
terraform init && terraform plan && terraform apply
```

No Route53 module here — production uses the apex zone directly (see that environment's `main.tf`
comment).

## After this: what's not done yet

- `environments/dr` — out of scope for this phase (`cloud-architecture-blueprint.md`'s pilot-light
  DR strategy means this account gets built out around the same time as Phase 3's EKS clusters,
  not before there's anything to make a DR copy of).
- IAM Identity Center — still manual-prerequisite-gated (`enable_identity_center = false`
  everywhere); enable it per `modules/organizations`' README once you're ready to onboard human
  users via SSO instead of the break-glass `OrganizationAccountAccessRole` path used throughout
  this guide.
- Every account's GitHub Actions workflow (`.github/workflows/*.yml` in this repository) —
  configuring CI to actually use the Terraform roles this phase created is Phase 7 (GitOps) work,
  explicitly out of scope here. Until then, every `terraform apply` in this guide is run locally
  by a human, exactly as shown above.
