# Regional AWS WAFv2 web ACL for an internet-facing ALB — the AWS-native edge protection that
# ADR-004 (as amended) puts in front of the Production API now that the ALB itself is public.
#
# Baseline only: AWS-managed rule groups, default action ALLOW. Deliberately NO custom blocking
# rules, NO geo restrictions and NO rate-based rules — mobile clients share carrier-grade NAT
# addresses, so an IP rate limit would throttle legitimate users long before it stopped an attack.
# Each managed group can be run in COUNT mode (observe without blocking) or have individual rules
# overridden to COUNT, so tuning is a variable change, never a code change.

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name_prefix}-${var.name_suffix}"
  description = var.description
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = { for group in var.managed_rule_groups : group.name => group }

    content {
      name     = "aws-${rule.value.name}"
      priority = rule.value.priority

      override_action {
        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
        dynamic "none" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.name

          dynamic "rule_action_override" {
            for_each = toset(rule.value.count_rule_names)
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-${rule.value.name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-${var.name_suffix}"
    sampled_requests_enabled   = var.sampled_requests_enabled
  }

  tags = merge(var.tags, { Application = "waf", Purpose = "${var.name_suffix}-web-acl" })
}

# --- Logging (var.logging_enabled) ---------------------------------------------------------------------
# WAF requires the destination log group name to start with "aws-waf-logs-". Authorization headers
# and cookies are redacted — request logs must never become a credential store.

resource "aws_cloudwatch_log_group" "this" {
  count = var.logging_enabled ? 1 : 0

  name              = "aws-waf-logs-${var.name_prefix}-${var.name_suffix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Application = "waf", Purpose = "${var.name_suffix}-web-acl-logs" })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.logging_enabled ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.this[0].arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  dynamic "logging_filter" {
    for_each = var.log_only_non_allowed_requests ? [1] : []
    content {
      default_behavior = "DROP"

      filter {
        behavior    = "KEEP"
        requirement = "MEETS_ANY"

        condition {
          action_condition {
            action = "BLOCK"
          }
        }

        condition {
          action_condition {
            action = "COUNT"
          }
        }
      }
    }
  }
}
