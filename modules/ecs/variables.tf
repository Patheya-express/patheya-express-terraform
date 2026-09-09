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
  description = "From module.ecr's repository_urls[\"api-gateway\"] — the single image family that serves API, worker, and migration (docs/infrastructure/workers.md in the backend repo: worker and migration are the same image with a different command/entrypoint, never a separate repository)."
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

variable "api_readiness_path" {
  description = "The application's existing readiness endpoint — used by the ALB target group (module.alb), not this module directly, but kept here so the container health check below stays in sync with the same contract."
  type        = string
  default     = "/api/v1/health/ready"
}

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
