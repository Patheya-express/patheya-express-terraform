# modules/backup-vault

One `aws_backup_vault`. Exists as its own module — rather than an inline resource in an
environment's `main.tf` — purely to satisfy platform-standards.md Section 9's "an environment
directory only calls modules, never defines a raw AWS resource directly," specifically for the
one resource in Phase 4 that a domain-specific module (`modules/aurora`) can't own itself: the
DR-region vault, created by passing a `provider = aws.dr` alias at the call site
(`environments/<env>/data/main.tf`).

## Usage

```hcl
provider "aws" {
  alias  = "dr"
  region = "ap-southeast-1"
}

module "kms_dr" {
  source    = "../../../modules/kms"
  providers = { aws = aws.dr }
  # ...
}

module "aurora_backup_vault_dr" {
  source      = "../../../modules/backup-vault"
  providers   = { aws = aws.dr }
  tags        = module.shared.tags
  name        = "${module.shared.name_prefix}-aurora-vault-dr"
  kms_key_arn = module.kms_dr.key_arns["aurora-backup-dr"]
}
```

## Vault Lock

`enable_vault_lock` (default `false`) turns on AWS Backup Vault Lock. Left off by default
deliberately — once its cooling-off period (`vault_lock_changeable_for_days`, default 3) passes,
the lock cannot be loosened or removed by anyone, including the account root user. Turning it on
is a per-environment human decision, not something this module defaults into. `modules/aurora`'s
primary vault exposes the identical set of variables, so both the primary and DR copies of a given
environment's backups can be locked consistently rather than one protected and the other not.

## Inputs / Outputs

See `variables.tf` / `outputs.tf`.
