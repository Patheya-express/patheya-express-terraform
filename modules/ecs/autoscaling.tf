# Application Auto Scaling — only in service_management_mode = "ci_autoscaled", where it (not
# Terraform) owns each service's desired_count. Terraform owns the bounds: changing min/max here is
# how an operating-mode change (docs/production-lifecycle.md) scales a service, including to zero
# (min = max = 0). RegisterScalableTarget moves the current task count into the new [min, max]
# range immediately, so a bound change takes effect on apply without touching desired_count.
#
# Target tracking on average CPU and memory per service. The worker has no queue-depth metric
# published today (BullMQ backlog is not exported to CloudWatch), so it scales on the same resource
# signals as the API rather than on an invented metric.

locals {
  autoscaled_services = local.ci_managed ? {
    api = {
      service_name = local.api_service_name
      min_capacity = var.api_min_capacity
      max_capacity = var.api_max_capacity
    }
    worker = {
      service_name = local.worker_service_name
      min_capacity = var.worker_min_capacity
      max_capacity = var.worker_max_capacity
    }
  } : {}

  autoscaling_metrics = {
    cpu    = { predefined_metric = "ECSServiceAverageCPUUtilization", target = var.autoscaling_cpu_target_percent }
    memory = { predefined_metric = "ECSServiceAverageMemoryUtilization", target = var.autoscaling_memory_target_percent }
  }

  autoscaling_policies = {
    for pair in setproduct(keys(local.autoscaled_services), keys(local.autoscaling_metrics)) :
    "${pair[0]}-${pair[1]}" => {
      service = pair[0]
      metric  = local.autoscaling_metrics[pair[1]]
    }
  }
}

resource "aws_appautoscaling_target" "service" {
  for_each = local.autoscaled_services

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${each.value.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.min_capacity
  max_capacity       = each.value.max_capacity

  tags = merge(var.tags, { Application = "ecs", Purpose = "${each.key}-scalable-target" })

  depends_on = [aws_ecs_service.api_ci_managed, aws_ecs_service.worker_ci_managed]
}

resource "aws_appautoscaling_policy" "target_tracking" {
  for_each = local.autoscaling_policies

  name               = "${var.name_prefix}-${each.key}-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service[each.value.service].service_namespace
  resource_id        = aws_appautoscaling_target.service[each.value.service].resource_id
  scalable_dimension = aws_appautoscaling_target.service[each.value.service].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.metric.target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown_seconds
    scale_out_cooldown = var.autoscaling_scale_out_cooldown_seconds

    predefined_metric_specification {
      predefined_metric_type = each.value.metric.predefined_metric
    }
  }
}
