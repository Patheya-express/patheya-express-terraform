# modules/ecr

One ECR repository per app (five total — `api-gateway` shared by the backend's `worker`
Deployment, plus the four frontend apps), immutable tags, KMS encryption, scan-on-push + continuous
rescanning, a two-rule lifecycle policy, and org-wide cross-account pull.

Deployed once, in `environments/shared-services` — the "shared image registry" account per
`cloud-architecture-blueprint.md` Section 2's account table.

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  tags             = module.shared.tags
  kms_key_arn      = module.kms.key_arns["ecr"]
  organization_id  = module.organizations.organization_id
}
```
