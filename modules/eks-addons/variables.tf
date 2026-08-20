variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Without the leading https:// — e.g. \"oidc.eks.ap-south-1.amazonaws.com/id/XXXX\"."
  type        = string
}

variable "node_role_name" {
  description = "From module.eks — the role Karpenter-launched nodes assume, referenced by name in the EC2NodeClass's instance profile."
  type        = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "eks_node_security_group_id" {
  type = string
}

variable "route53_zone_id" {
  description = "This environment's Route53 zone (delegated subdomain for dev/staging, the apex zone for production — cloud-architecture-blueprint.md Section 6) — scopes ExternalDNS and cert-manager's DNS-01 solver to exactly this zone, never every zone in the account."
  type        = string
}

variable "domain_filter" {
  description = "e.g. \"dev.patheyaexpress.com\" — ExternalDNS only manages records under this domain."
  type        = string
}

variable "acm_certificate_arn" {
  description = "From module.route53 (Phase 2) — used by the NLB the AWS Load Balancer Controller provisions in front of NGINX Ingress for TLS termination."
  type        = string
}

variable "app_secrets_arns" {
  description = <<-EOT
    Phase 9 (Enterprise Workload Deployment): the four human-populated application secrets
    (data/main.tf's module.secrets_manager `external_credential_secrets` — jwt-signing-key,
    cloudinary, razorpay, smtp) synced into a single `backend-app-secrets` Kubernetes Secret,
    completing the pattern backend-database-url/backend-redis-credentials already established.
    Keys must be exactly: "jwt-signing-key", "cloudinary", "razorpay", "smtp" — matching
    data/outputs.tf's external_credential_secret_arns map keys.
  EOT
  type        = map(string)
}

variable "karpenter_instance_families" {
  description = "Instance families Karpenter may launch across, for spot-diversification (cloud-architecture-blueprint.md Section 14) — never a single family, so a capacity shortage in one family doesn't stall scale-up."
  type        = list(string)
  default     = ["m6i", "m6a", "m5", "m5a"]
}

variable "environment_tier" {
  description = "development | staging | production — drives NGINX Ingress replica count, PDB minAvailable, and Karpenter's on-demand-vs-spot default weighting."
  type        = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment_tier)
    error_message = "environment_tier must be one of: development, staging, production."
  }
}

# --- Phase 4 (Data Platform) additions below — External Secrets Operator + PgBouncer ---

variable "aws_region" {
  description = "Region External Secrets Operator's ClusterSecretStore targets for Secrets Manager reads — always the same region this cluster runs in (no cross-region secret reads)."
  type        = string
}

variable "secrets_manager_path_prefix" {
  description = "From module.secrets-manager's secrets_path_prefix output (\"patheya-express/<environment>\") — scopes External Secrets Operator's IRSA policy to exactly this environment's secrets."
  type        = string
}

variable "aurora_master_secret_arn" {
  description = "From module.aurora's master_user_secret_arn — the RDS-managed credential PgBouncer's ExternalSecret syncs into a userlist Secret."
  type        = string
}

variable "redis_auth_token_secret_arn" {
  description = "From module.secrets-manager's redis_auth_token_secret_arn."
  type        = string
}

variable "aurora_writer_endpoint" {
  type = string
}

variable "aurora_reader_endpoint" {
  description = "Null when the environment has no reader instances (development) — PgBouncer's read pool then also targets the writer endpoint."
  type        = string
  default     = null
}

variable "aurora_port" {
  type = number
}

variable "aurora_database_name" {
  type = string
}

variable "pgbouncer_replica_count" {
  type    = number
  default = 2
}

variable "pgbouncer_pdb_min_available" {
  type    = number
  default = 1
}

variable "redis_primary_endpoint" {
  description = "From module.elasticache — used when num_shards = 1 (no configuration_endpoint published)."
  type        = string
}

variable "redis_configuration_endpoint" {
  description = "From module.elasticache — set only when num_shards > 1 (production)."
  type        = string
  default     = null
}

variable "redis_port" {
  type = number
}
