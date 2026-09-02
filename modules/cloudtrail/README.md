# modules/cloudtrail

An organization-wide, multi-region CloudTrail trail with log file validation, split across two
accounts by design (separation of duties):

- **`environments/security`** calls this module with `create_destination_bucket = true,
  create_trail = false` — owns the S3 log archive (versioned, KMS-encrypted, Object Lock in
  GOVERNANCE mode for `object_lock_retention_days` (default 400), lifecycle-transitioned to
  Glacier after a year, bucket policy scoped to exactly the management account's trail ARN). Object
  Lock can only be enabled at bucket creation — see `enable_object_lock`'s description before ever
  setting it `false` on a bucket that's already been applied for real.
- **`environments/management`** calls it with `create_trail = true, create_destination_bucket =
  false, existing_bucket_name = <security account's bucket, via terraform_remote_state>` — owns the
  trail resource itself (org trails can only be created by the management account) and a
  CloudWatch Logs feed for real-time querying/alerting.

This split means even an account with `AdministratorAccess` in the management account can't
tamper with the log archive's retention/versioning without also having access to the security
account — exactly the separation-of-duties CloudTrail is supposed to provide.

## Usage

```hcl
# environments/security/main.tf
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  tags        = module.shared.tags
  name_prefix = "patheya-express" # org-wide resource, not per-environment

  create_destination_bucket = true
  create_trail              = false
  organization_id           = module.organizations.organization_id # read via remote state from environments/management
  management_account_id     = "<management account ID>"
  kms_key_arn                = module.kms.key_arns["cloudtrail-logs"]
}
```

```hcl
# environments/management/main.tf
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  tags        = module.shared.tags
  name_prefix = "patheya-express"

  create_destination_bucket = false
  create_trail              = true
  existing_bucket_name       = data.terraform_remote_state.security.outputs.cloudtrail_bucket_name
  kms_key_arn                 = module.kms.key_arns["cloudtrail-logs"]
}
```
