# Phase 0 remediation (audit finding: no notification path exists from GuardDuty or Security Hub
# findings to a human — unlike modules/supply-chain-security's Falco/Kyverno/Trivy findings, which
# already route through Alertmanager). EventBridge -> SNS is the standard, no-secret-required
# AWS-native pattern for this. What's implemented here in Terraform: the SNS topic, its encryption
# and publish policy, and the two EventBridge rules that route findings above a severity floor to
# it. What's deliberately left as a documented configuration requirement, not implemented here: a
# real subscriber (finding_notification_emails, populated via tfvars once a real address exists —
# this repository does not invent one) and any deeper integration (AWS Chatbot -> Slack, a
# PagerDuty AWS integration) that itself requires a human-supplied credential/webhook, the same
# boundary modules/observability's Alertmanager secrets already draw.

resource "aws_sns_topic" "findings" {
  count = var.enable_finding_notifications ? 1 : 0

  name              = "${var.name_prefix}-security-findings"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Application = "security", Purpose = "finding-notifications" })
}

# Independent final review, second pass: the ARNs of the EventBridge rules actually created below
# — built conditionally, mirroring each rule's own count expression exactly, since
# enable_guardduty/enable_security_hub can each independently be false (and referencing
# resource[0] is only ever evaluated on the branch where that same condition guarantees the
# resource exists — the same short-circuiting ternary idiom this module already uses for
# local.oidc_provider_arn elsewhere in this repository). Feeds the confused-deputy condition below.
locals {
  finding_notification_rule_arns = concat(
    var.enable_finding_notifications && var.enable_guardduty ? [aws_cloudwatch_event_rule.guardduty_findings[0].arn] : [],
    var.enable_finding_notifications && var.enable_security_hub ? [aws_cloudwatch_event_rule.security_hub_findings[0].arn] : [],
  )
}

data "aws_iam_policy_document" "findings_topic_policy" {
  count = var.enable_finding_notifications ? 1 : 0

  statement {
    sid     = "AllowEventBridgeToPublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.findings[0].arn]

    # Confused-deputy protection (independent final review, second pass) — the AWS-recommended
    # pattern for an EventBridge -> SNS publish path: scopes the grant to the exact rule(s) this
    # module creates, not to any EventBridge rule anywhere that happens to target this topic ARN.
    # aws:SourceAccount is deliberately NOT added alongside this: the rule ARNs already embed this
    # account's ID and region, so an exact-ARN match already provides everything SourceAccount
    # would add — a second condition here would be redundant, not additional protection. If
    # neither GuardDuty nor Security Hub notifications are enabled, this list is empty and the
    # condition can never match, which correctly means nothing can publish via this statement at
    # all (there would be no legitimate publisher in that case either).
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = local.finding_notification_rule_arns
    }
  }
}

resource "aws_sns_topic_policy" "findings" {
  count = var.enable_finding_notifications ? 1 : 0

  arn    = aws_sns_topic.findings[0].arn
  policy = data.aws_iam_policy_document.findings_topic_policy[0].json
}

resource "aws_sns_topic_subscription" "findings_email" {
  for_each = var.enable_finding_notifications ? toset(var.finding_notification_emails) : toset([])

  topic_arn = aws_sns_topic.findings[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# GuardDuty severity bands are numeric: LOW 1.0-3.9, MEDIUM 4.0-6.9, HIGH 7.0-8.9, CRITICAL
# 9.0-10.0 (AWS's own scale). Routing MEDIUM+ matches the signal-to-noise bar
# modules/supply-chain-security's own alerting already uses elsewhere in this repository — LOW
# findings are high-volume and mostly informational, not page-worthy.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_finding_notifications && var.enable_guardduty ? 1 : 0

  name        = "${var.name_prefix}-guardduty-findings-to-sns"
  description = "Routes GuardDuty findings (severity >= 4.0, i.e. MEDIUM and above) to the security-findings SNS topic."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })

  tags = merge(var.tags, { Application = "security", Purpose = "guardduty-finding-notification-rule" })
}

resource "aws_cloudwatch_event_target" "guardduty_findings_to_sns" {
  count = var.enable_finding_notifications && var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "security-findings-sns"
  arn       = aws_sns_topic.findings[0].arn
}

# Security Hub's finding-format severity is a separate field (Severity.Label) from GuardDuty's
# numeric scale above — HIGH/CRITICAL only, and Workflow.Status = NEW so a finding already being
# worked (NOTIFIED/RESOLVED/SUPPRESSED) doesn't re-notify on every subsequent import.
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  count = var.enable_finding_notifications && var.enable_security_hub ? 1 : 0

  name        = "${var.name_prefix}-security-hub-findings-to-sns"
  description = "Routes Security Hub findings (HIGH/CRITICAL severity, workflow status NEW) to the security-findings SNS topic."

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["HIGH", "CRITICAL"] }
        Workflow = { Status = ["NEW"] }
      }
    }
  })

  tags = merge(var.tags, { Application = "security", Purpose = "security-hub-finding-notification-rule" })
}

resource "aws_cloudwatch_event_target" "security_hub_findings_to_sns" {
  count = var.enable_finding_notifications && var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "security-findings-sns"
  arn       = aws_sns_topic.findings[0].arn
}
