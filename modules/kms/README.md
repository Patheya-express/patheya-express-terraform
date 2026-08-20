# modules/kms

One customer-managed KMS key (+ alias, automatic annual rotation per
`docs/architecture/platform-standards.md` Section 13) per data class, keyed by an arbitrary map —
"one CMK per data class per environment, not one shared key across everything" per
`cloud-architecture-blueprint.md` Section 11.

## Phase 2 usage

Only `cloudtrail-logs` and `ecr` are instantiated in this phase's environments — `aurora`,
`redis`/`elasticache`, and `ebs` keys are added when Phase 3/4 actually provisions those services,
not created idle ahead of need (`platform-standards.md` Section 1, principle 2).

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
