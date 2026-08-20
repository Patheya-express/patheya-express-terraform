# modules/route53

One hosted zone + one DNS-validated wildcard ACM certificate — used both for the apex zone
(`patheyaexpress.com`, created once in `environments/shared-services`) and for each environment's
delegated subdomain (`dev.patheyaexpress.com` in `environments/development`, etc.), per
`platform-standards.md` Section 6.

## Delegation

This module does not itself create the NS delegation record in a parent zone — a delegated
subdomain zone and its parent almost always live in different AWS accounts (different Terraform
state), so the delegation wiring is a cross-environment concern handled in
`environments/shared-services/route53-delegation.tf` via `terraform_remote_state` reads of each
environment's `name_servers` output, not inside this module.

## Usage

```hcl
# environments/development/main.tf
module "route53" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "dev.patheyaexpress.com"
}
```

```hcl
# environments/shared-services/main.tf — the apex zone
module "route53_apex" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "patheyaexpress.com"
}
```

## CloudFront's us-east-1 ACM requirement

Not accommodated here — CloudFront (`cloud-architecture-blueprint.md` Section 7's future
S3-backed static path) isn't in scope yet. See `versions.tf`'s note for what to add when that
work starts.
