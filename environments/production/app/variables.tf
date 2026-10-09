variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "operating_mode" {
  description = <<-EOT
    Production lifecycle state for the application runtime — idle | build | live
    (docs/production-lifecycle.md). Deliberately no default; set in the committed
    operating-mode.auto.tfvars.
      idle  — API and worker scaled to 0 (Application Auto Scaling min = max = 0). The ALB stays
              and answers 503; no application task runs, so no traffic reaches the data tier.
      build — API 1, worker 1, fixed. Exercises the real task shapes without production scale.
      live  — production capacity with target-tracking autoscaling.
  EOT
  type        = string

  validation {
    condition     = contains(["idle", "build", "live"], var.operating_mode)
    error_message = "operating_mode must be one of: idle, build, live."
  }
}

variable "bootstrap_image_tag" {
  description = "The release tag (<semver>-<git-sha-short>) for the initial task-definition revisions — must already exist in the shared-services api-gateway repository with its \"-migrate\" sibling. After the first apply, backend-deploy-ecs.yml owns the running image; changing this only affects the revision Terraform itself registers."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9a-f]{7,40}$", var.bootstrap_image_tag))
    error_message = "bootstrap_image_tag must be an immutable release tag of the form <semver>-<git-sha> (e.g. 1.4.0-a1b2c3d), never a floating tag such as latest."
  }
}

variable "apex_domain" {
  type    = string
  default = "patheyaexpress.com"
}

variable "api_hostname" {
  description = "Label under var.apex_domain for the public API (ALB) — mobile apps and web apps call https://<api_hostname>.<apex_domain>."
  type        = string
  default     = "api"
}

variable "static_sites" {
  description = "Static web apps served from S3 + CloudFront, keyed by modules/static-site site key, valued by hostname label under var.apex_domain. Keys must match the root layer's var.static_sites (the frontend deploy role's bucket scope) — asserted by a check block."
  type        = map(string)
  default = {
    admin      = "admin"
    customer   = "customer"
    restaurant = "restaurant"
    delivery   = "delivery"
  }
}

variable "fargate_on_demand_vcpu_quota" {
  description = "The account's applied \"Fargate On-Demand vCPU resource count\" quota (L-3032A538) in this region — 30 as audited 2026-10-02. The plan fails if live-mode peak capacity, including rolling-deployment surge, could exceed it."
  type        = number
  default     = 30
}

variable "shared_services_account_id" {
  description = "Owns the api-gateway ECR repository (environments/shared-services)."
  type        = string
  default     = "668506406019"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be a 12-digit AWS account ID."
  }
}
