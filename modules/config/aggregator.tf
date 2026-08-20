# Organization-wide compliance visibility from one place (environments/security only) — requires
# AWS Config to be a trusted org service (enabled via modules/organizations' aws_service_access_principals)
# and this account to be the Config delegated administrator (set once, manually or via a separate
# aws_organizations_delegated_administrator resource in environments/security — see that
# environment's own main.tf).
resource "aws_config_configuration_aggregator" "organization" {
  count = var.create_aggregator ? 1 : 0

  name = "${var.name_prefix}-organization-aggregator"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.aggregator[0].arn
  }

  tags = merge(var.tags, { Application = "config", Purpose = "organization-wide-compliance-aggregator" })
}

data "aws_iam_policy_document" "aggregator_assume" {
  count = var.create_aggregator ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aggregator" {
  count = var.create_aggregator ? 1 : 0

  name               = "${var.name_prefix}-config-aggregator-role"
  assume_role_policy = data.aws_iam_policy_document.aggregator_assume[0].json

  tags = merge(var.tags, { Application = "config", Purpose = "config-aggregator-role" })
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  count = var.create_aggregator ? 1 : 0

  role       = aws_iam_role.aggregator[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}
