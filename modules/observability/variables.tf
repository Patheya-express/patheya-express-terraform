variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "environment_tier" {
  type = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment_tier)
    error_message = "environment_tier must be one of: development, staging, production."
  }
}

variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "kms_key_arn" {
  description = "Encrypts the Loki/Tempo S3 buckets and the Grafana admin credential secret — this environment's \"observability\" KMS key."
  type        = string
}

variable "storage_class_name" {
  description = "From module.eks_addons's default_storage_class output — Prometheus/Alertmanager/Grafana PVCs reuse the same gp3 StorageClass every other stateful in-cluster workload uses, not a new one."
  type        = string
}

variable "alertmanager_slack_webhook_secret_arn" {
  description = "From a modules/secrets-manager call in platform/main.tf — an empty container a human populates; see docs/alerting-guide.md."
  type        = string
}

variable "alertmanager_pagerduty_key_secret_arn" {
  description = "Same pattern as the Slack webhook secret."
  type        = string
}

variable "secrets_manager_path_prefix" {
  description = "patheya-express/<environment> — used only to build this module's own Grafana-admin secret name consistently with Phase 4's convention; this module does not read Phase 4's secrets."
  type        = string
}

# --- Sizing knobs, defaulted per environment_tier by the caller (environments/<env>/platform) ---

variable "prometheus_replicas" {
  type    = number
  default = 1
}

variable "prometheus_retention" {
  type    = string
  default = "15d"
}

variable "prometheus_storage_size" {
  type    = string
  default = "50Gi"
}

variable "alertmanager_replicas" {
  type    = number
  default = 1
}

variable "grafana_replicas" {
  type    = number
  default = 1
}

variable "loki_deployment_mode" {
  description = "SingleBinary (development/staging) or SimpleScalable (production) — see docs/loki-guide.md."
  type        = string
  default     = "SingleBinary"
}

variable "loki_retention_days" {
  type    = number
  default = 7
}

variable "tempo_retention_hours" {
  type    = number
  default = 168 # 7 days — traces are far higher-volume than logs; a shorter retention than Loki's is standard practice
}

variable "otel_sampling_ratio" {
  description = "Head-based probabilistic sampling ratio (0.0-1.0) for the OTel Collector's traces pipeline. 1.0 in development/staging (full visibility while the app is new), lower in production once real trace volume exists."
  type        = number
  default     = 1.0
}
