variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  description = "From module.networking's alb_security_group_id output (create_ecs_topology_security_groups = true) — already restricted to Cloudflare's published IP ranges on 443."
  type        = string
}

variable "certificate_arn" {
  description = <<-EOT
    ACM certificate ARN for the ALB's HTTPS listener. This module does NOT create or request a
    certificate — the caller must provision one (in this region, ap-south-1 — unlike CloudFront,
    an ALB certificate has no us-east-1 requirement) and pass its ARN explicitly. No default: an
    invented or assumed certificate is exactly the kind of silent architecture decision this
    module must not make.
  EOT
  type        = string
}

variable "target_port" {
  description = "The API container's listening port — the target group's forwarded port."
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "The application's existing readiness endpoint."
  type        = string
  default     = "/api/v1/health/ready"
}

variable "health_check_interval_seconds" {
  type    = number
  default = 30
}

variable "health_check_timeout_seconds" {
  type    = number
  default = 5
}

variable "healthy_threshold" {
  type    = number
  default = 2
}

variable "unhealthy_threshold" {
  type    = number
  default = 3
}

variable "idle_timeout_seconds" {
  description = "Raised above the ALB default (60s) to accommodate WebSocket connections that may sit idle between Socket.IO events without being torn down mid-session."
  type        = number
  default     = 300
}

variable "enable_deletion_protection" {
  description = "false is appropriate ONLY for a temporary, intentionally-destroyable environment."
  type        = bool
  default     = false
}
