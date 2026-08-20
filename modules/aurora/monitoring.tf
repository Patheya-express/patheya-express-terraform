# Database Observability Foundation (this task's Section 9) — CloudWatch-native alarms only.
# No Prometheus/Grafana dashboard here by explicit scope; these alarms are what pages someone
# before Phase 5's dashboards exist to make the same conditions visually obvious.

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora writer CPU > 80% for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.id
    Role                = "WRITER"
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  alarm_name          = "${var.name_prefix}-aurora-freeable-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 268435456 # 256 MiB — a hard floor regardless of instance size; below this, OOM risk is imminent
  alarm_description   = "Aurora writer freeable memory below 256MiB for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.id
    Role                = "WRITER"
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "memory-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.name_prefix}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  # PgBouncer (this task's Section 2) is precisely what keeps this number low regardless of
  # api-gateway's HPA replica count — a sustained breach here means PgBouncer itself is
  # misconfigured or bypassed, not that the application needs more Aurora connections
  # (cloud-architecture-blueprint.md Section 5's stated reason PgBouncer exists at all).
  threshold          = var.serverless ? 400 : 1000
  alarm_description  = "Aurora writer connection count elevated for 3 consecutive minutes — check PgBouncer pool sizing before assuming Aurora needs to scale."
  alarm_actions      = [var.alarm_sns_topic_arn]
  ok_actions         = [var.alarm_sns_topic_arn]
  treat_missing_data = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.id
    Role                = "WRITER"
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "connections-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "replica_lag_high" {
  count = var.reader_count > 0 ? 1 : 0

  alarm_name          = "${var.name_prefix}-aurora-replica-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1000 # ms — Aurora's storage-layer replication is typically single-digit ms; 1s is already well into "something is wrong" territory
  alarm_description   = "Aurora reader replica lag above 1000ms for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.id
    Role                = "READER"
  }

  tags = merge(var.tags, { Application = "aurora", Purpose = "replica-lag-alarm" })
}
