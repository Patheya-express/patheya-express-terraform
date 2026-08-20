# A bare SNS topic — no subscriptions. Phase 5 (Observability) is what wires PagerDuty/Slack
# subscriptions into this topic; this phase's job (Section 9 — "no Prometheus yet") is only to
# give every CloudWatch alarm this phase creates a real, existing notification target to point
# `alarm_actions` at, rather than either leaving alarms actionless or inventing a premature
# PagerDuty/Slack integration this phase has no scope to configure.
resource "aws_sns_topic" "this" {
  name              = "${var.name_prefix}-${var.topic_name}"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Application = "alerting", Purpose = var.topic_name })
}

resource "aws_sns_topic_policy" "this" {
  arn = aws_sns_topic.this.arn

  policy = data.aws_iam_policy_document.topic_policy.json
}

data "aws_iam_policy_document" "topic_policy" {
  statement {
    sid     = "AllowCloudWatchAlarmsToPublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.this.arn]
  }
}
