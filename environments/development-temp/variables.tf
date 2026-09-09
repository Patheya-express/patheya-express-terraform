variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "organization_id" {
  description = "AWS Organization ID (o-3aodwvvzk1) — scopes module.ecr's cross-account pull policy to org members only. Not used for anything else; this root never calls modules/organizations."
  type        = string
}

# --- Networking ----------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "A deliberately distinct range (10.90.0.0/16) — not one of the sequential 10.10/10.20/10.30 blocks the eventual real development/staging/production VPCs use, signaling \"temporary, out-of-band\" and avoiding any future peering/Transit-Gateway CIDR collision even though this VPC lives in a different account than those."
  type        = string
  default     = "10.90.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "Exactly 3 Availability Zones are required (modules/vpc's own requirement)."
  }
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.90.0.0/24", "10.90.1.0/24", "10.90.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.90.16.0/20", "10.90.32.0/20", "10.90.48.0/20"]
}

variable "private_data_subnet_cidrs" {
  type    = list(string)
  default = ["10.90.64.0/24", "10.90.65.0/24", "10.90.66.0/24"]
}

variable "cloudflare_ipv4_cidrs" {
  description = <<-EOT
    Cloudflare's current published IPv4 edge ranges (https://www.cloudflare.com/ips-v4/) — used
    for BOTH module.networking's required nlb_allowed_cidrs (an existing, unused-here NLB security
    group this module also unconditionally creates for every caller — see Phase 2 report §H for
    why that's left untouched) and the new alb_allowed_cidrs this root actually uses. Required, no
    default: this repository does not hardcode Cloudflare's IP list anywhere, since it changes
    over time.
  EOT
  type        = list(string)
}

# --- Application image -----------------------------------------------------------------------------

variable "image_tag" {
  description = "The api-gateway image tag to deploy (API + worker containers; \"<tag>-migrate\" is derived automatically for the migration task). No default — see modules/ecs's identical variable for why."
  type        = string
}

# --- Certificates ----------------------------------------------------------------------------------

variable "alb_certificate_arn" {
  description = "ACM certificate ARN, in ap-south-1, for the ALB's HTTPS listener (api.qa.patheyaexpress.com). This root does not request or validate a certificate itself."
  type        = string
}

variable "frontend_acm_certificate_arn" {
  description = "ACM certificate ARN, in us-east-1 (CloudFront's hard requirement, regardless of this repository's ap-south-1 primary region), covering every domain in var.frontend_domains — a single wildcard (*.qa.patheyaexpress.com) or SAN certificate. This root does not request or validate a certificate itself."
  type        = string
}

# --- Domains (taken from the approved architecture / the frontend repository's own existing
#     per-app-subdomain convention — never invented) --------------------------------------------

variable "frontend_domains" {
  type = map(string)
  default = {
    customer   = "customer.qa.patheyaexpress.com"
    restaurant = "restaurant.qa.patheyaexpress.com"
    admin      = "admin.qa.patheyaexpress.com"
    delivery   = "delivery.qa.patheyaexpress.com"
  }
}

variable "api_domain" {
  type    = string
  default = "api.qa.patheyaexpress.com"
}

# --- IAM (cross-root coordination — see modules/ecs/variables.tf's permission_boundary_arn) -----

variable "permission_boundary_arn" {
  description = <<-EOT
    ARN of the Security account's permission boundary policy, created by environments/security's
    own module.iam call — NOT computed by this root, and NOT created by this root. Deterministic
    value once environments/security is applied: arn:aws:iam::512206886196:policy/patheya-security-permission-boundary.
    This root does not verify the policy exists (that would require a live AWS data-source lookup,
    which this Phase 2 implementation deliberately avoids — see the Phase 2 report's IAM/OIDC
    coordination section). If environments/security has not yet been applied, applying this root
    for real will fail at that point with a clear AWS-side error, not silently invent a second
    boundary.
  EOT
  type        = string
}

# --- Notifications (minimal — Phase 1 §14's deliberately non-overbuilt observability) -----------

variable "alert_email_addresses" {
  description = "Subscribed to the alarm SNS topic this root creates directly (ElastiCache CPU/memory, no other alarms wired yet). Defaults to empty — this repository does not invent a real address."
  type        = list(string)
  default     = []
}

# --- Non-secret application configuration --------------------------------------------------------

variable "app_non_secret_environment" {
  description = <<-EOT
    Additional plain (non-secret) environment variables to merge into the API/worker containers,
    on top of the ones this root already derives (NODE_ENV, PORT, the four *_APP_URL origins,
    REDIS_HOST/PORT/TLS, API_PUBLIC_URL, STORAGE_DRIVER). Use this for anything genuinely
    non-secret this root doesn't already compute — never a credential-shaped value.
  EOT
  type        = map(string)
  default     = {}
}
