# ElastiCache publishes these engine metrics per node (CacheClusterId), not per replication group —
# alarms on a ReplicationGroupId dimension match no data and sit in INSUFFICIENT_DATA. The alarms
# watch the first node, named "<group>-001" ("<group>-0001-001" in cluster mode). That is the
# primary while there are no replicas (Production); with replicas and automatic failover the
# primary can move, and per-node alarms would be needed. ReplicationLag is reported by replicas,
# so its alarm (HA only) watches the first replica.
locals {
  alarm_cache_cluster_id = format(
    var.cluster_mode_enabled ? "%s-0001-001" : "%s-001",
    aws_elasticache_replication_group.this.replication_group_id,
  )
  alarm_replica_cache_cluster_id = format(
    var.cluster_mode_enabled ? "%s-0001-002" : "%s-002",
    aws_elasticache_replication_group.this.replication_group_id,
  )
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis engine CPU > 80% for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    CacheClusterId = local.alarm_cache_cluster_id
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "cpu-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.name_prefix}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory usage > 80% for 3 consecutive minutes — eviction risk for BullMQ delayed jobs and cached data alike."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    CacheClusterId = local.alarm_cache_cluster_id
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "memory-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.name_prefix}-redis-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 8000 # ElastiCache's own connection ceiling scales with node type; this is a conservative cross-node-type floor worth paging on regardless of instance size
  alarm_description   = "Redis connection count elevated for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "missing"

  dimensions = {
    CacheClusterId = local.alarm_cache_cluster_id
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "connections-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "replication_lag_high" {
  count = local.ha_enabled ? 1 : 0

  alarm_name          = "${var.name_prefix}-redis-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ReplicationLag"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Maximum"
  threshold           = 5 # seconds
  alarm_description   = "Redis replica lag above 5s for 3 consecutive minutes."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = local.alarm_replica_cache_cluster_id
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "replication-lag-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "evictions_high" {
  alarm_name          = "${var.name_prefix}-redis-evictions-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Any key eviction in a 3-minute window — BullMQ job data or presence/tracking cache is being evicted, not just expiring."
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = local.alarm_cache_cluster_id
  }

  tags = merge(var.tags, { Application = "elasticache", Purpose = "evictions-alarm" })
}
