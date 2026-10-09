# Application Auto Scaling — only in service_management_mode = "ci_autoscaled", where it (not
# Terraform) owns each service's desired_count. Terraform owns the bounds: changing min/max here is
# how an operating-mode change (docs/production-lifecycle.md) scales a service, including to zero
# (min = max = 0). RegisterScalableTarget moves the current task count into the new [min, max]
# range immediately, so a bound change takes effect on apply without touching desired_count.
#
# Target tracking on average CPU and memory per service, with an optional per-service CPU target.
# The API can additionally track ALB requests per target (api_alb_request_count_target), which
# reacts to a traffic ramp before CPU saturates. The worker has no queue-depth metric published
# today (BullMQ backlog is not exported to CloudWatch), so it scales on resource signals only
# rather than on an invented metric. With several policies on one target, Application Auto Scaling
# scales out if any policy asks to and scales in only when all of them allow it.

locals {
  autoscaled_services = local.ci_managed ? {
    api = {
      service_name = local.api_service_name
      min_capacity = var.api_min_capacity
      max_capacity = var.api_max_capacity
      cpu_target   = coalesce(var.api_autoscaling_cpu_target_percent, var.autoscaling_cpu_target_percent)
    }
    worker = {
      service_name = local.worker_service_name
      min_capacity = var.worker_min_capacity
      max_capacity = var.worker_max_capacity
      cpu_target   = coalesce(var.worker_autoscaling_cpu_target_percent, var.autoscaling_cpu_target_percent)
    }
  } : {}

  # Keys "<service>-cpu" / "<service>-memory" are unchanged from the shared-target version, so the
  # existing policies update in place.
  autoscaling_policies = merge(
    {
      for svc, cfg in local.autoscaled_services : "${svc}-cpu" => {
        service           = svc
        predefined_metric = "ECSServiceAverageCPUUtilization"
        target            = cfg.cpu_target
        resource_label    = null
      }
    },
    {
      for svc, cfg in local.autoscaled_services : "${svc}-memory" => {
        service           = svc
        predefined_metric = "ECSServiceAverageMemoryUtilization"
        target            = var.autoscaling_memory_target_percent
        resource_label    = null
      }
    },
    local.ci_managed && var.api_alb_request_count_target != null ? {
      "api-requests" = {
        service           = "api"
        predefined_metric = "ALBRequestCountPerTarget"
        target            = var.api_alb_request_count_target
        resource_label    = var.api_alb_resource_label
      }
    } : {},
  )
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
    target_value       = each.value.target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown_seconds
    scale_out_cooldown = var.autoscaling_scale_out_cooldown_seconds

    predefined_metric_specification {
      predefined_metric_type = each.value.predefined_metric
      resource_label         = each.value.resource_label
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.predefined_metric != "ALBRequestCountPerTarget" || try(length(each.value.resource_label) > 0, false)
      error_message = "api_alb_request_count_target requires api_alb_resource_label (\"<alb_arn_suffix>/<target_group_arn_suffix>\")."
    }
  }
}
