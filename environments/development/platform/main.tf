data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-433985779683"
    key    = "development/cluster/terraform.tfstate"
    region = "ap-south-1"
  }
}

# Phase 4 — same-account read of the data/ stage's outputs (Aurora/ElastiCache/Secrets Manager),
# same reasoning as the cluster/ read above.
data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-433985779683"
    key    = "development/data/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "development"
  application = "eks-addons"
  purpose     = "Development EKS platform add-ons (Karpenter, ingress, DNS, cert-manager, storage)"
  retention   = "n/a"
}

module "eks_addons" {
  source = "../../../modules/eks-addons"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  cluster_name               = data.terraform_remote_state.cluster.outputs.cluster_name
  vpc_id                     = data.terraform_remote_state.cluster.outputs.vpc_id
  oidc_provider_arn          = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url          = data.terraform_remote_state.cluster.outputs.oidc_provider_url
  node_role_name             = data.terraform_remote_state.cluster.outputs.node_role_name
  private_app_subnet_ids     = data.terraform_remote_state.cluster.outputs.private_app_subnet_ids
  eks_node_security_group_id = data.terraform_remote_state.cluster.outputs.eks_node_security_group_id

  route53_zone_id     = data.terraform_remote_state.cluster.outputs.route53_zone_id
  domain_filter       = "dev.patheyaexpress.com"
  acm_certificate_arn = data.terraform_remote_state.cluster.outputs.acm_certificate_arn

  environment_tier = "development"

  # Phase 4 — External Secrets Operator + PgBouncer
  aws_region                   = var.aws_region
  secrets_manager_path_prefix  = data.terraform_remote_state.data.outputs.secrets_path_prefix
  aurora_master_secret_arn     = data.terraform_remote_state.data.outputs.aurora_master_secret_arn
  redis_auth_token_secret_arn  = data.terraform_remote_state.data.outputs.redis_auth_token_secret_arn
  aurora_writer_endpoint       = data.terraform_remote_state.data.outputs.aurora_writer_endpoint
  aurora_reader_endpoint       = data.terraform_remote_state.data.outputs.aurora_reader_endpoint
  aurora_port                  = data.terraform_remote_state.data.outputs.aurora_port
  aurora_database_name         = data.terraform_remote_state.data.outputs.aurora_database_name
  redis_primary_endpoint       = data.terraform_remote_state.data.outputs.redis_primary_endpoint
  redis_configuration_endpoint = data.terraform_remote_state.data.outputs.redis_configuration_endpoint
  redis_port                   = data.terraform_remote_state.data.outputs.redis_port

  # Phase 9 — the four human-populated application secrets (jwt-signing-key/cloudinary/razorpay/
  # smtp), synced into `backend-app-secrets` alongside backend-database-url/backend-redis-credentials.
  app_secrets_arns = data.terraform_remote_state.data.outputs.external_credential_secret_arns

  pgbouncer_replica_count     = 1 # development — single replica, matching k8s/overlays/development's lower-HA posture
  pgbouncer_pdb_min_available = 0 # single-replica PDB with minAvailable=1 would block all voluntary disruption; 0 is deliberate for a 1-replica dev pool
}

# Phase 5 — Observability. A new KMS key (Loki/Tempo S3 buckets, Grafana admin credential) and a
# second modules/secrets-manager call (Alertmanager's two placeholder receiver secrets) — same
# module Phase 4 already uses, different call site and different secret names, so nothing
# collides with Phase 4's own secrets-manager call in environments/development/data.
module "kms_observability" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    observability = {
      description         = "Encrypts the Loki/Tempo S3 buckets and the Grafana admin credential"
      additional_services = ["s3.amazonaws.com", "secretsmanager.amazonaws.com"]
    }
  }
}

module "secrets_manager_observability" {
  source = "../../../modules/secrets-manager"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "development"
  kms_key_arn = module.kms_observability.key_arns["observability"]

  external_credential_secrets = ["alertmanager-slack-webhook", "alertmanager-pagerduty-key"]
}

module "observability" {
  source = "../../../modules/observability"

  tags             = module.shared.tags
  name_prefix      = module.shared.name_prefix
  environment_tier = "development"
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  aws_region       = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.cluster.outputs.oidc_provider_url

  kms_key_arn        = module.kms_observability.key_arns["observability"]
  storage_class_name = module.eks_addons.default_storage_class

  alertmanager_slack_webhook_secret_arn = module.secrets_manager_observability.external_credential_secret_arns["alertmanager-slack-webhook"]
  alertmanager_pagerduty_key_secret_arn = module.secrets_manager_observability.external_credential_secret_arns["alertmanager-pagerduty-key"]
  secrets_manager_path_prefix           = module.secrets_manager_observability.secrets_path_prefix

  prometheus_replicas     = 1
  prometheus_retention    = "7d"
  prometheus_storage_size = "20Gi"
  alertmanager_replicas   = 1
  grafana_replicas        = 1
  loki_deployment_mode    = "SingleBinary"
  loki_retention_days     = 7
  tempo_retention_hours   = 72
  otel_sampling_ratio     = 1.0

  depends_on = [module.eks_addons]
}

# ArgoCD — the deployment engine (bootstrap -> platform -> infrastructure -> applications).
# See modules/argocd's README for the full ownership-boundary rationale.
module "secrets_manager_argocd" {
  source = "../../../modules/secrets-manager"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "development"
  kms_key_arn = module.kms_observability.key_arns["observability"] # reuses the same KMS key Phase 5 already created in this state — a fourth key for one more placeholder secret isn't warranted

  external_credential_secrets = ["argocd-repo-credentials"]
}

module "argocd" {
  source = "../../../modules/argocd"

  tags               = module.shared.tags
  name_prefix        = module.shared.name_prefix
  environment_tier   = "development"
  storage_class_name = module.eks_addons.default_storage_class

  gitops_repo_url  = "https://github.com/patheya-express/patheya-express-gitops.git"
  backend_repo_url = "https://github.com/patheya-express/patheya-express-platform.git"

  repo_credentials_secret_arn = module.secrets_manager_argocd.external_credential_secret_arns["argocd-repo-credentials"]

  depends_on = [module.eks_addons]
}

# Phase 7 — Enterprise Supply Chain Security. Kyverno/Trivy Operator/Falco.
module "supply_chain_security" {
  source = "../../../modules/supply-chain-security"

  tags               = module.shared.tags
  name_prefix        = module.shared.name_prefix
  environment_tier   = "development"
  cluster_name       = data.terraform_remote_state.cluster.outputs.cluster_name
  aws_region         = var.aws_region
  storage_class_name = module.eks_addons.default_storage_class

  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.cluster.outputs.oidc_provider_url

  ecr_registry_host     = var.ecr_registry_host
  alertmanager_endpoint = module.observability.alertmanager_service_dns

  # development gets Audit for the baseline best-practice policies (fast iteration while nothing
  # is deployed yet) but the SAME Enforce default as every environment for image signature
  # verification — this phase's core guarantee doesn't get a softer development mode.
  kyverno_policy_mode = "Audit"

  depends_on = [module.eks_addons, module.observability, module.argocd]
}
