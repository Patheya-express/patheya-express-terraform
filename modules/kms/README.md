# modules/kms

One customer-managed KMS key (+ alias, automatic annual rotation per
`docs/architecture/platform-standards.md` Section 13) per data class, keyed by an arbitrary map —
"one CMK per data class per environment, not one shared key across everything" per
`cloud-architecture-blueprint.md` Section 11.

## Usage

Called once per environment, per data class actually in use in that environment — no key is
created idle ahead of a real consumer needing it (`platform-standards.md` Section 1, principle 2).
`environments/*/main.tf` (the root/foundation layer) instantiates `cloudtrail-logs`, `ecr` (in
`shared-services`), and `eks-secrets` (from `environments/*/cluster`); `environments/*/data`
instantiates `aurora`, `redis`, and `secrets`; the DR-region provider alias instantiates
`aurora-backup-dr`.

```hcl
module "kms" {
  source = "../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    cloudtrail-logs = {
      description         = "Encrypts CloudTrail log delivery to CloudWatch Logs and S3"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com"]
    }
    ecr = {
      description         = "Encrypts ECR repository images"
      additional_services = ["ecr.amazonaws.com"]
    }
  }
}
```
