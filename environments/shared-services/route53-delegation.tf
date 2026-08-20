# NS delegation records in the apex zone, pointing at each environment's own delegated subdomain
# zone (environments/{development,staging}/main.tf's route53 module — production uses the apex
# zone directly, no delegation needed for it). Name servers are supplied as tfvars, copied in
# after each environment's first apply (docs/bootstrap-guide.md) — not read via
# terraform_remote_state, since that would require this account's Terraform role to have
# cross-account read access to each workload account's separate state bucket, a real IAM grant
# this repository doesn't provision (each account's state bucket is intentionally
# account-isolated per platform-standards.md Section 9). Explicit tfvars is the simpler, equally
# correct alternative for this small, fixed number of cross-account values.

resource "aws_route53_record" "development_delegation" {
  count = length(var.development_zone_name_servers) > 0 ? 1 : 0

  zone_id = module.route53_apex.zone_id
  name    = "dev.patheyaexpress.com"
  type    = "NS"
  ttl     = 172800
  records = var.development_zone_name_servers
}

resource "aws_route53_record" "staging_delegation" {
  count = length(var.staging_zone_name_servers) > 0 ? 1 : 0

  zone_id = module.route53_apex.zone_id
  name    = "staging.patheyaexpress.com"
  type    = "NS"
  ttl     = 172800
  records = var.staging_zone_name_servers
}
