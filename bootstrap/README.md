# bootstrap/

Creates the S3 state bucket and DynamoDB lock table that every `environments/*/backend.tf` in this
repository depends on. This is the one configuration in the repo that intentionally runs with
**local** state — it cannot use the remote backend it hasn't created yet.

Run once per AWS account (management, security, shared-services, development, staging, production,
disaster-recovery — `cloud-architecture-blueprint.md` Section 2's seven accounts), by someone
holding real credentials for that account, from a clean local checkout:

```bash
cd bootstrap
terraform init
terraform apply \
  -var="account_alias=management" \
  -var="account_id=<12-digit-account-id>"
```

After `apply` succeeds, **move the resulting local state into the bucket it just created** so a
second run of this same bootstrap config (e.g. by a different engineer, or in CI) doesn't overwrite
it — add an S3 backend block to this directory's own `versions.tf` pointing at the bucket/table the
`apply` just output, then:

```bash
terraform init -migrate-state
```

...and delete the local `terraform.tfstate*` files once `init -migrate-state` confirms the migration.
This is a manual, one-time, per-account procedure — not something `terraform apply` from
`environments/` ever triggers automatically.

See `docs/bootstrap-guide.md` for the full, ordered sequence across all seven accounts.
