# Production's records in the apex zone (patheyaexpress.com).
#
# Production uses the apex zone directly — "production has no environment prefix"
# (platform-standards.md Section 6) — so there is no delegated Production subzone to hand over.
# Instead, Production's app layer (environments/production/app) assumes this role to manage
# exactly its own records: api., admin. and the secondary web hostnames, plus their ACM
# DNS-validation records. The role cannot touch the apex record, the NS/SOA records, the
# dev./staging. delegations, or any other name.
#
# Trusted principals: Production's Terraform CI role and its IAM Identity Center
# PlatformAdministrator role (human applies) — nothing else in that account.

locals {
  apex_zone_name = "patheyaexpress.com"

  production_dns_record_patterns = flatten([
    for label in var.production_dns_hostnames : [
      "${label}.${local.apex_zone_name}",
      "_*.${label}.${local.apex_zone_name}",
    ]
  ])
}

data "aws_iam_policy_document" "production_dns_trust" {
  statement {
    sid     = "ProductionTerraformPrincipals"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.production_account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${var.production_account_id}:role/patheya-production-terraform-role",
        "arn:aws:iam::${var.production_account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_PlatformAdministrator_*",
      ]
    }
  }
}

resource "aws_iam_role" "production_dns" {
  name                 = "${module.shared.name_prefix}-production-dns-records-role"
  description          = "Assumed by Production's app layer to manage its own records in the ${local.apex_zone_name} apex zone."
  assume_role_policy   = data.aws_iam_policy_document.production_dns_trust.json
  permissions_boundary = module.iam.permission_boundary_arn
  max_session_duration = 3600

  tags = merge(module.shared.tags, { Application = "route53", Purpose = "production-dns-records-role" })

  # module.iam.permission_boundary_arn is a computed ARN string, not a reference to the boundary
  # policy resource, so it carries no dependency on its own — without this, the role can be created
  # before the boundary policy exists (CreateRole: "Scope ARN ... does not exist").
  depends_on = [module.iam]
}

data "aws_iam_policy_document" "production_dns" {
  # Zone discovery for the app layer's `data "aws_route53_zone"` lookup.
  statement {
    sid       = "DiscoverZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadApexZone"
    effect    = "Allow"
    actions   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = [module.route53_apex.zone_arn]
  }

  # Writes only for Production's own names (route53:ChangeResourceRecordSetsNormalizedRecordNames
  # is lower-case, without the trailing dot).
  statement {
    sid       = "ManageProductionRecordsOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [module.route53_apex.zone_arn]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = local.production_dns_record_patterns
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["A", "AAAA", "CNAME"]
    }
  }
}

resource "aws_iam_role_policy" "production_dns" {
  name   = "${module.shared.name_prefix}-production-dns-records-policy"
  role   = aws_iam_role.production_dns.id
  policy = data.aws_iam_policy_document.production_dns.json
}
