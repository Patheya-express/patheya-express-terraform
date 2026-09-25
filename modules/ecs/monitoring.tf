resource "aws_cloudwatch_metric_alarm" "api_cpu_high" {
  alarm_name          = "${var.name_prefix}-ecs-api-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "API service CPU > 80% of its reserved 512 CPU units, sustained for 15 minutes. Informational only — no autoscaling exists."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.api.name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "api_memory_high" {
  alarm_name          = "${var.name_prefix}-ecs-api-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "API service memory > 80% of its reserved 1024 MiB, sustained for 15 minutes. Informational only — no autoscaling exists."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.api.name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "api-memory-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  alarm_name          = "${var.name_prefix}-ecs-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Worker service CPU > 80% of its reserved 256 CPU units, sustained for 15 minutes. Informational only — no autoscaling exists."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.worker.name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "worker_memory_high" {
  alarm_name          = "${var.name_prefix}-ecs-worker-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Worker service memory > 80% of its reserved 512 MiB, sustained for 15 minutes. Informational only — no autoscaling exists."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ServiceName = aws_ecs_service.worker.name
    ClusterName = aws_ecs_cluster.this.name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-memory-alarm" })
}
