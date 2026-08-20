resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/patheya-express/${var.name_prefix}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.flow_log_kms_key_arn

  tags = merge(var.tags, {
    Application = "networking"
    Purpose     = "vpc-flow-logs"
  })
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = merge(var.tags, { Application = "networking", Purpose = "vpc-flow-logs-delivery-role" })
}

data "aws_iam_policy_document" "flow_logs_delivery" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_delivery" {
  name   = "${var.name_prefix}-vpc-flow-logs-delivery"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_delivery.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = var.vpc_id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60 # 1-minute aggregation — the fastest interval, favoring incident-response granularity over the marginal cost saving of the 10-minute option

  tags = merge(var.tags, { Application = "networking", Purpose = "vpc-flow-log" })
}
