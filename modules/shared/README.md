# modules/shared

Computed-output-only module (no AWS resources) providing the two things every other module needs
and must not re-derive independently: the mandatory tag map
(`docs/architecture/platform-standards.md` Section 5, fourteen keys) and the `patheya-<environment>`
naming prefix (Section 4).

## Usage

```hcl
module "shared" {
  source = "../../modules/shared"

  environment = "production"
  application = "vpc"
  purpose     = "Primary VPC for the production environment"
  retention   = "n/a"
}

resource "aws_vpc" "this" {
  cidr_block = "10.30.0.0/16"
  tags       = merge(module.shared.tags, { Name = "${module.shared.name_prefix}-vpc" })
}
```

## Inputs

| Name | Description | Default |
| --- | --- | --- |
| `environment` | `management` / `development` / `staging` / `production` | — (required) |
| `application` | The specific app/component this resource serves | — (required) |
| `purpose` | One-line human-readable description | — (required) |
| `retention` | Actual configured retention, or `"n/a"` | — (required) |
| `owner` | Accountable team | `platform-engineering` |
| `cost_center` | Chargeback cost center | `eng-platform` |
| `repository` | IaC source repository | `patheya-express-terraform` |
| `resource_version` | Deployed app version, if applicable | `n/a` |
| `confidentiality` | `public` / `internal` / `confidential` / `restricted` | `internal` |
| `business_unit` | Business unit | `engineering` |
| `compliance` | Compliance classification, or `none` | `none` |
| `tags_extra` | Additional tags merged on top of the mandatory fourteen | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `tags` | Complete mandatory tag map |
| `name_prefix` | `patheya-<environment>` |
