# modules/config

AWS Config: a recorder (all supported resource types, including global resources) + delivery
channel + KMS-encrypted S3 archive, deployed identically in **every** account (management,
security, shared-services, development, staging, production, dr) — unlike CloudTrail, Config's
recorder is genuinely per-account, not an org-wide singleton.

## Compliance rules

Ten AWS Config managed rules, the concrete enforcement mechanism behind:

- **This task's Section 11** ("Reject any resource missing mandatory tags") — the `REQUIRED_TAGS`
  managed rule, split across three rule instances since AWS Config only accepts 6 tag keys per
  rule and there are fourteen mandatory tags (`platform-standards.md` Section 5).
- Baseline security posture: S3 public-read denial, S3 TLS enforcement, EBS encryption, root MFA,
  zero IAM user inline policies (should always evaluate COMPLIANT given `platform-standards.md`'s
  no-IAM-users stance — a NON_COMPLIANT finding here means that stance was violated somewhere),
  VPC Flow Logs enabled.

## Organization aggregator

`create_aggregator = true` only in `environments/security` — one dashboard for compliance status
across every account, rather than checking each account's Config console individually.

## Usage

```hcl
module "config" {
  source = "../../modules/config"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  create_aggregator = false # true only in environments/security
}
```
