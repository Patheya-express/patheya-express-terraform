variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  description = "Used only in CloudWatch log group naming — not for conditional logic."
  type        = string
}

# --- Networking ----------------------------------------------------------------------------------

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "ecs_task_security_group_id" {
  description = "From module.networking's ecs_task_security_group_id output (create_ecs_topology_security_groups = true)."
  type        = string
}

variable "alb_target_group_arn" {
  description = "From module.alb — the API service's only load_balancer attachment. The worker service has none."
  type        = string
}

# --- Image -----------------------------------------------------------------------------------------

variable "image_repository_url" {
  description = "From module.ecr's repository_urls[\"api-gateway\"] (or the shared-services repository's URL when pulling cross-account — see image_repository_arn) — the single image family that serves API, worker, and migration (docs/infrastructure/workers.md in the backend repo: worker and migration are the same image with a different command/entrypoint, never a separate repository)."
  type        = string
}

variable "image_tag" {
  description = "The tag to deploy for the API and worker containers (e.g. a release SHA or semver tag published by the existing backend CI pipeline). No default — an unpinned \"latest\" is never appropriate for a task definition Terraform manages."
  type        = string
}

variable "migration_image_tag_suffix" {
  description = "Appended to var.image_tag for the migration task's image reference (e.g. \"<tag>-migrate\") — matches the backend Dockerfile's existing `migrate` build stage, which is pushed as a `-migrate`-suffixed tag to the same repository. Do not invent a different migration image strategy."
  type        = string
  default     = "-migrate"
}

variable "api_container_port" {
  type    = number
  default = 3000
}

# --- Task sizing -------------------------------------------------------------------------------

variable "api_cpu" {
  type    = number
  default = 512 # 0.5 vCPU
}

variable "api_memory" {
  type    = number
  default = 1024 # 1 GB
}

variable "worker_cpu" {
  type    = number
  default = 256 # 0.25 vCPU
}

variable "worker_memory" {
  type    = number
  default = 512 # 0.5 GB
}

variable "migration_cpu" {
  type    = number
  default = 256
}

variable "migration_memory" {
  type    = number
  default = 512
}

variable "api_desired_count" {
  description = "1 for initial temporary DEV+QA — safe at 1 because the application's Socket.IO Redis adapter (already implemented; see apps/api-gateway/src/modules/realtime/gateways/realtime.gateway.ts) makes no sticky-session assumption, so raising this later requires no architecture change."
  type        = number
  default     = 1
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

# --- Health checks -----------------------------------------------------------------------------

variable "liveness_path" {
  description = "The application's existing liveness endpoint (no dependency checks) — used for the ECS container-level health check on both API and worker containers, matching the backend Dockerfile's own HEALTHCHECK target."
  type        = string
  default     = "/api/v1/health/live"
}

# --- Logging -----------------------------------------------------------------------------------

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "kms_key_arn" {
  description = "Encrypts the CloudWatch log groups this module creates."
  type        = string
}

# --- Secrets (Secrets Manager ARNs only — never a literal value) -------------------------------

variable "database_url_secret_arn" {
  description = "From module.rds's database_url_secret_arn output. Injected into API, worker, and migration containers as DATABASE_URL via ECS `secrets`, never as a plaintext environment value."
  type        = string
}

variable "app_secrets" {
  description = <<-EOT
    Map of environment-variable name to Secrets Manager secret ARN, injected via ECS `secrets`
    into the API and worker containers only (never the migration task, which needs only
    DATABASE_URL). Expected keys, matching apps/api-gateway/src/config/env.validation.ts's
    SECRET-classified variables: JWT_ACCESS_SECRET, JWT_REFRESH_SECRET, RAZORPAY_KEY_ID,
    RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET,
    REDIS_AUTH_TOKEN, SMTP_USER, SMTP_PASS, BANK_ACCOUNT_ENCRYPTION_KEY, SUPER_ADMIN_PASSWORD.
    The caller (environments/development-temp) supplies the actual ARNs from module.secrets_manager
    and module.elasticache — this module never creates a secret itself.
  EOT
  type        = map(string)
}

# --- Non-secret configuration --------------------------------------------------------------------

variable "app_environment" {
  description = <<-EOT
    Map of environment-variable name to plaintext value, injected via ECS `environment` into the
    API and worker containers only — for genuinely non-secret configuration (NODE_ENV, PORT,
    STORAGE_DRIVER, LOG_LEVEL, the four *_APP_URL CORS origins, REDIS_HOST, REDIS_PORT, REDIS_TLS,
    CLOUDINARY_CLOUD_NAME, SMTP_HOST/PORT/FROM, KAFKA_BROKER placeholder, etc.). Never put a
    credential-shaped value here — use app_secrets instead.
  EOT
  type        = map(string)
  default     = {}
}

# --- IAM -----------------------------------------------------------------------------------------

variable "permission_boundary_arn" {
  description = <<-EOT
    ARN of the Security account's existing permission boundary policy, created by
    modules/iam (this module does NOT compute the ARN itself, e.g. via
    "$${var.name_prefix}-permission-boundary", because environments/development-temp and
    environments/security are two independent Terraform roots sharing one AWS account, and
    the boundary must be owned by exactly one of them: environments/security's own module.iam
    call). This is a required, explicit input rather than a computed value specifically so the
    dependency is undismissable: if environments/security has not yet been applied (and this
    policy therefore does not exist in the account), applying this module's roles will fail at
    apply time with a clear AWS-side error, not silently create a second, competing boundary
    architecture. See docs (Phase 1.5 investigation) for the deterministic ARN pattern:
    arn:aws:iam::<security-account-id>:policy/patheya-security-permission-boundary — assuming
    environments/security passes environment = "security" to module.shared, as it already does.
  EOT
  type        = string
}

# --- Monitoring ------------------------------------------------------------------------------------

variable "alarm_sns_topic_arn" {
  description = "Alarms still evaluate and appear in CloudWatch with this unset, but notify no one — always pass this."
  type        = string
}

variable "api_min_running_tasks_alarm_threshold" {
  description = "Service-health alarm: fires when the API service's RunningTaskCount (Container Insights) stays below this for 3 minutes. null (default) creates no alarm. Requires container_insights != \"disabled\"."
  type        = number
  default     = null
}

variable "worker_min_running_tasks_alarm_threshold" {
  description = "Service-health alarm for the worker service — see api_min_running_tasks_alarm_threshold."
  type        = number
  default     = null
}

# --- Service management / capacity -----------------------------------------------------------------

variable "service_management_mode" {
  description = <<-EOT
    Who owns the running image revision and the task count (see main.tf's Services section):
      "terraform"     (default) — Terraform owns both: var.image_tag and api/worker_desired_count.
      "ci_autoscaled" — CI owns the task-definition revision (a release registers a new revision
                        and updates the service); Application Auto Scaling owns desired_count
                        within the api/worker_min/max_capacity bounds below. Terraform still owns
                        every other setting. var.image_tag is then only the bootstrap image.
  EOT
  type        = string
  default     = "terraform"

  validation {
    condition     = contains(["terraform", "ci_autoscaled"], var.service_management_mode)
    error_message = "service_management_mode must be \"terraform\" or \"ci_autoscaled\"."
  }
}

variable "api_min_capacity" {
  description = "Application Auto Scaling lower bound for the API service (ci_autoscaled only). 0 scales the service to zero (idle mode)."
  type        = number
  default     = null

  validation {
    condition = var.service_management_mode != "ci_autoscaled" || (
      var.api_min_capacity != null && var.api_max_capacity != null &&
      try(var.api_min_capacity >= 0 && var.api_min_capacity <= var.api_max_capacity, false)
    )
    error_message = "ci_autoscaled requires api_min_capacity and api_max_capacity, with 0 <= min <= max."
  }
}

variable "api_max_capacity" {
  description = "Application Auto Scaling upper bound for the API service (ci_autoscaled only)."
  type        = number
  default     = null
}

variable "worker_min_capacity" {
  description = "Application Auto Scaling lower bound for the worker service (ci_autoscaled only)."
  type        = number
  default     = null

  validation {
    condition = var.service_management_mode != "ci_autoscaled" || (
      var.worker_min_capacity != null && var.worker_max_capacity != null &&
      try(var.worker_min_capacity >= 0 && var.worker_min_capacity <= var.worker_max_capacity, false)
    )
    error_message = "ci_autoscaled requires worker_min_capacity and worker_max_capacity, with 0 <= min <= max."
  }
}

variable "worker_max_capacity" {
  description = "Application Auto Scaling upper bound for the worker service (ci_autoscaled only)."
  type        = number
  default     = null
}

variable "autoscaling_cpu_target_percent" {
  description = "Target-tracking goal for average service CPU utilization."
  type        = number
  default     = 60
}

variable "api_autoscaling_cpu_target_percent" {
  description = "API CPU target-tracking goal. null (default) uses autoscaling_cpu_target_percent."
  type        = number
  default     = null
}

variable "worker_autoscaling_cpu_target_percent" {
  description = "Worker CPU target-tracking goal. null (default) uses autoscaling_cpu_target_percent."
  type        = number
  default     = null
}

variable "api_alb_request_count_target" {
  description = "ALBRequestCountPerTarget goal for the API (requests per target per minute). null (default) adds no request-based policy."
  type        = number
  default     = null

  validation {
    condition     = var.api_alb_request_count_target == null || try(var.api_alb_request_count_target > 0, false)
    error_message = "api_alb_request_count_target must be positive when set."
  }
}

variable "api_alb_resource_label" {
  description = "ALBRequestCountPerTarget resource label, \"<alb_arn_suffix>/<target_group_arn_suffix>\" (modules/alb outputs). Required when api_alb_request_count_target is set."
  type        = string
  default     = null
}

variable "autoscaling_memory_target_percent" {
  description = "Target-tracking goal for average service memory utilization."
  type        = number
  default     = 75
}

variable "autoscaling_scale_in_cooldown_seconds" {
  type    = number
  default = 300
}

variable "autoscaling_scale_out_cooldown_seconds" {
  type    = number
  default = 60
}

variable "deployment_minimum_healthy_percent" {
  description = "Rolling-deployment floor, as a percentage of desired count."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Rolling-deployment ceiling, as a percentage of desired count. With the default 200, a service at N tasks briefly runs up to 2N during a deploy — callers must size their max capacities so that surge fits the account's Fargate vCPU quota."
  type        = number
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100
    error_message = "deployment_maximum_percent must be at least 100."
  }
}

variable "api_health_check_grace_period_seconds" {
  description = "Seconds ECS ignores ALB health-check failures after an API task starts. null (default) leaves the ECS default (0)."
  type        = number
  default     = null
}

# --- Platform / hardening -------------------------------------------------------------------------

variable "container_insights" {
  description = "ECS cluster containerInsights setting. \"disabled\" (default) is development-temp's deliberately minimal choice; Production enables it (it is also what publishes the RunningTaskCount metric the service-health alarms use)."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "enabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be \"disabled\", \"enabled\" or \"enhanced\"."
  }
}

variable "enable_execute_command" {
  description = "ECS Exec — the operational access mechanism into running API/worker tasks (replaces kubectl exec). Adds the SSM message-channel permissions to the API/worker task roles and an init process to their containers."
  type        = bool
  default     = false
}

variable "stop_timeout_seconds" {
  description = "Seconds between SIGTERM and SIGKILL for API/worker containers. null (default) leaves the Fargate default (30s). Must exceed the application's SHUTDOWN_TIMEOUT_MS."
  type        = number
  default     = null

  validation {
    condition     = var.stop_timeout_seconds == null || try(var.stop_timeout_seconds >= 2 && var.stop_timeout_seconds <= 120, false)
    error_message = "stop_timeout_seconds must be between 2 and 120 (Fargate's limit)."
  }
}

variable "readonly_root_filesystem" {
  description = "Mounts the API/worker containers' root filesystem read-only. Pair with writable_container_paths for any directory the application genuinely writes to."
  type        = bool
  default     = false
}

variable "writable_container_paths" {
  description = "Container paths given a writable ephemeral (task-storage) bind mount — Fargate's substitute for tmpfs, which Fargate does not support. Empty by default."
  type        = list(string)
  default     = []
}

# --- Cross-account image / secrets ------------------------------------------------------------------

variable "image_repository_arn" {
  description = "ARN of the ECR repository at var.image_repository_url. When set, the execution role's pull permissions are scoped to exactly this repository — required when images live in another account (Production pulls from shared-services). null (default) keeps the original scope: this account's own repositories."
  type        = string
  default     = null
}

variable "secrets_kms_key_arns" {
  description = "Additional KMS keys the execution role may decrypt with when resolving `secrets` — needed when secrets are encrypted with a different key than var.kms_key_arn (Production: the data layer's secrets key). var.kms_key_arn is always included."
  type        = list(string)
  default     = []
}

variable "migration_database_url_secret_arn" {
  description = "Secrets Manager ARN injected as DATABASE_URL into the migration task only. null (default) reuses var.database_url_secret_arn. Production sets this to the migrator user's direct-to-writer URL so migration and runtime credentials stay separate."
  type        = string
  default     = null
}
