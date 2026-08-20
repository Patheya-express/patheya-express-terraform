# Three IRSA roles — Loki and Tempo need S3 access for their storage backends; Grafana needs
# read-only CloudWatch access so its Aurora/Redis/PgBouncer dashboards (Phase 4's alarms/metrics
# already exist there, this phase only needs to *read* them) don't require duplicating Aurora/
# Redis metrics into Prometheus via a separate CloudWatch exporter deployment.

data "aws_iam_policy_document" "loki_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:logging:loki"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = "${var.name_prefix}-loki-role"
  assume_role_policy = data.aws_iam_policy_document.loki_assume.json

  tags = merge(var.tags, { Application = "observability", Purpose = "loki-irsa-role" })
}

data "aws_iam_policy_document" "loki" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "loki" {
  name   = "${var.name_prefix}-loki-policy"
  role   = aws_iam_role.loki.id
  policy = data.aws_iam_policy_document.loki.json
}

data "aws_iam_policy_document" "tempo_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:tracing:tempo"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tempo" {
  name               = "${var.name_prefix}-tempo-role"
  assume_role_policy = data.aws_iam_policy_document.tempo_assume.json

  tags = merge(var.tags, { Application = "observability", Purpose = "tempo-irsa-role" })
}

data "aws_iam_policy_document" "tempo" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.tempo.arn, "${aws_s3_bucket.tempo.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "tempo" {
  name   = "${var.name_prefix}-tempo-policy"
  role   = aws_iam_role.tempo.id
  policy = data.aws_iam_policy_document.tempo.json
}

data "aws_iam_policy_document" "grafana_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:monitoring:kube-prometheus-stack-grafana"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${var.name_prefix}-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json

  tags = merge(var.tags, { Application = "observability", Purpose = "grafana-cloudwatch-irsa-role" })
}

# Read-only, and only the specific CloudWatch read actions the CloudWatch datasource's query
# editor needs — never cloudwatch:PutMetricData or any mutating action.
data "aws_iam_policy_document" "grafana" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarmsForMetric", "cloudwatch:DescribeAlarms",
      "logs:DescribeLogGroups", "logs:GetLogGroupFields", "logs:StartQuery", "logs:StopQuery",
      "logs:GetQueryResults", "logs:GetLogEvents",
      "tag:GetResources",
    ]
    resources = ["*"] # CloudWatch's read/query API surface has no per-resource ARN scoping for these actions — the same "unscoped read" pattern already used in modules/eks-addons's Karpenter/ALB Controller policies
  }
}

resource "aws_iam_role_policy" "grafana" {
  name   = "${var.name_prefix}-grafana-policy"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana.json
}
