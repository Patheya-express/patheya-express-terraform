# One AWS Budget per member account (platform-standards.md Section 20), alerting at 50/80/100% of
# forecast — created here, in the management account, using each member account's ID as the
# `cost_filter`, since consolidated billing means all member-account spend is visible from
# management without needing a budget resource deployed inside each member account individually.

resource "aws_budgets_budget" "member_account" {
  for_each = var.member_accounts

  name         = "patheya-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd[each.key])
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [aws_organizations_account.member[each.key].id]
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.budget_notification_emails
    }
  }
}
