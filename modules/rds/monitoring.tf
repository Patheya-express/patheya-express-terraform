resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "RDS connections > 90 (~80% of db.t4g.micro's ~112 effective max_connections) sustained for 15 minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  tags = merge(var.tags, { Application = "rds", Purpose = "connections-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80% sustained for 15 minutes (3x5min) — db.t4g.micro burst credits likely exhausted."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  tags = merge(var.tags, { Application = "rds", Purpose = "cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "free_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 4294967296 # 4 GiB — 20% of the current 20 GB allocation, above the ~2 GB point where storage autoscaling itself would engage
  alarm_description   = "RDS free storage below 4 GiB (20% of the current 20 GB allocation) for 10 minutes — above the ~2 GB point where storage autoscaling itself would engage."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  tags = merge(var.tags, { Application = "rds", Purpose = "storage-alarm" })
}
