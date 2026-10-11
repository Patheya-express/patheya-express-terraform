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
  alarm_description   = "API service CPU > 80% of its reserved ${var.api_cpu} CPU units, sustained for 15 minutes. ${local.ci_managed ? "Target-tracking autoscaling is active — a sustained breach means the service is at max capacity." : "Informational only — no autoscaling exists."}"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = local.api_service.name
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
  alarm_description   = "API service memory > 80% of its reserved ${var.api_memory} MiB, sustained for 15 minutes. ${local.ci_managed ? "Target-tracking autoscaling is active — a sustained breach means the service is at max capacity." : "Informational only — no autoscaling exists."}"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = local.api_service.name
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
  alarm_description   = "Worker service CPU > 80% of its reserved ${var.worker_cpu} CPU units, sustained for 15 minutes. ${local.ci_managed ? "Target-tracking autoscaling is active — a sustained breach means the service is at max capacity." : "Informational only — no autoscaling exists."}"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = local.worker_service.name
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
  alarm_description   = "Worker service memory > 80% of its reserved ${var.worker_memory} MiB, sustained for 15 minutes. ${local.ci_managed ? "Target-tracking autoscaling is active — a sustained breach means the service is at max capacity." : "Informational only — no autoscaling exists."}"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    ServiceName = local.worker_service.name
    ClusterName = aws_ecs_cluster.this.name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "worker-memory-alarm" })
}

# Service health — running task count below a floor (Container Insights' RunningTaskCount). Missing
# data is treated as breaching: a service with zero running tasks publishes nothing at all.
locals {
  running_task_alarms = {
    for k, v in {
      api    = { service_name = local.api_service.name, threshold = var.api_min_running_tasks_alarm_threshold }
      worker = { service_name = local.worker_service.name, threshold = var.worker_min_running_tasks_alarm_threshold }
    } : k => v if v.threshold != null && var.container_insights != "disabled"
  }
}

resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  for_each = local.running_task_alarms

  alarm_name          = "${var.name_prefix}-ecs-${each.key}-running-tasks-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Minimum"
  threshold           = each.value.threshold
  alarm_description   = "${each.key} service has fewer than ${each.value.threshold} running tasks for 3 consecutive minutes — degraded capacity or a failing deployment."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = each.value.service_name
  }

  tags = merge(var.tags, { Application = "ecs", Purpose = "${each.key}-running-tasks-alarm" })
}

# --- Queue backlog (var.queue_metrics) ------------------------------------------------------------

# The worker stopped publishing (or never started): scaling on this metric is then frozen (no
# scale-out, no scale-in), so it is surfaced rather than silently tolerated. Missing data is the
# failure being detected, hence "breaching".
resource "aws_cloudwatch_metric_alarm" "queue_metrics_stale" {
  count = var.queue_metrics == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-queue-metrics-stale"
  alarm_description   = "No BullMQ backlog metrics from the worker for 10 minutes: the publisher is down or failing, and queue-based worker scaling is frozen."
  namespace           = var.queue_metrics.namespace
  metric_name         = "BacklogWaiting"
  dimensions          = { Environment = var.queue_metrics.environment }
  statistic           = "SampleCount"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  tags = merge(var.tags, { Application = "ecs", Purpose = "queue-metrics-stale-alarm" })
}

# Work is waiting longer than expected even if the backlog is small (e.g. a stuck concurrency-1
# queue) — a latency signal scaling alone does not cover.
resource "aws_cloudwatch_metric_alarm" "queue_oldest_waiting" {
  count = var.queue_metrics == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-queue-oldest-waiting-high"
  alarm_description   = "The oldest waiting BullMQ job has waited over ${var.queue_metrics.oldest_waiting_alarm_seconds} s for 5 consecutive minutes."
  namespace           = var.queue_metrics.namespace
  metric_name         = "OldestWaitingAgeSeconds"
  dimensions          = { Environment = var.queue_metrics.environment }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.queue_metrics.oldest_waiting_alarm_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]

  tags = merge(var.tags, { Application = "ecs", Purpose = "queue-oldest-waiting-alarm" })
}
