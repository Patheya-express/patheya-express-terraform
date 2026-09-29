data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/cluster/terraform.tfstate"
    region = "ap-south-1"
  }
}

# The data layer (Aurora/Redis/application secrets) exists only in live mode — build develops the
# platform without any production data store (docs/production-lifecycle.md). Not read at all in
# build, so a missing data state can never break a build-mode plan.
data "terraform_remote_state" "data" {
  count = local.data_layer_enabled ? 1 : 0

  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/data/terraform.tfstate"
    region = "ap-south-1"
  }
}

locals {
  data_layer_enabled = var.operating_mode == "live"
  data               = local.data_layer_enabled ? data.terraform_remote_state.data[0].outputs : null

  # Build keeps every component but runs the observability module's own small-footprint defaults;
  # live is the production sizing this file has always declared.
  observability = {
    build = {
      prometheus_replicas   = 1, prometheus_retention = "7d", prometheus_storage_size = "50Gi"
      alertmanager_replicas = 1, grafana_replicas = 1, loki_deployment_mode = "SingleBinary"
      loki_retention_days   = 7, tempo_retention_hours = 72, otel_sampling_ratio = 0.2
    }
    live = {
      prometheus_replicas   = 2, prometheus_retention = "15d", prometheus_storage_size = "100Gi"
      alertmanager_replicas = 3, grafana_replicas = 2, loki_deployment_mode = "SimpleScalable"
      loki_retention_days   = 30, tempo_retention_hours = 168, otel_sampling_ratio = 0.2
    }
  }[var.operating_mode]
}

module "shared" {
  source = "../../../modules/shared"

  environment = "production"
  application = "eks-addons"
  purpose     = "Production EKS platform add-ons (Karpenter, ingress, DNS, cert-manager, storage)"
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

  # Cross-account values (environments/shared-services owns the apex zone) — tfvars, not remote
  # state; see variables.tf.
  route53_zone_id     = var.apex_zone_id
  domain_filter       = "patheyaexpress.com"
  acm_certificate_arn = var.apex_certificate_arn

  environment_tier = "production"

  # vpc-cni, coredns and kube-proxy are EKS-managed add-ons owned by cluster/ (modules/eks
  # managed_addons) so a new cluster is healthy before this layer runs.
  manage_core_addons = false

  # Phase 4 — External Secrets Operator + PgBouncer. All null in build (no data layer).
  aws_region                   = var.aws_region
  data_layer_enabled           = local.data_layer_enabled
  secrets_manager_path_prefix  = local.data_layer_enabled ? local.data.secrets_path_prefix : null
  aurora_master_secret_arn     = local.data_layer_enabled ? local.data.aurora_master_secret_arn : null
  redis_auth_token_secret_arn  = local.data_layer_enabled ? local.data.redis_auth_token_secret_arn : null
  aurora_writer_endpoint       = local.data_layer_enabled ? local.data.aurora_writer_endpoint : null
  aurora_reader_endpoint       = local.data_layer_enabled ? local.data.aurora_reader_endpoint : null
  aurora_port                  = local.data_layer_enabled ? local.data.aurora_port : null
  aurora_database_name         = local.data_layer_enabled ? local.data.aurora_database_name : null
  redis_primary_endpoint       = local.data_layer_enabled ? local.data.redis_primary_endpoint : null
  redis_configuration_endpoint = local.data_layer_enabled ? local.data.redis_configuration_endpoint : null
  redis_port                   = local.data_layer_enabled ? local.data.redis_port : null

  # Phase 9 — see environments/development/platform/main.tf's comment.
  app_secrets_arns = local.data_layer_enabled ? local.data.external_credential_secret_arns : null

  pgbouncer_replica_count     = 3
  pgbouncer_pdb_min_available = 2
}

# Phase 5 — Observability.
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
  environment = "production"
  kms_key_arn = module.kms_observability.key_arns["observability"]

  external_credential_secrets = ["alertmanager-slack-webhook", "alertmanager-pagerduty-key"]
}

module "observability" {
  source = "../../../modules/observability"

  tags             = module.shared.tags
  name_prefix      = module.shared.name_prefix
  environment_tier = "production"
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  aws_region       = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.cluster.outputs.oidc_provider_url

  kms_key_arn        = module.kms_observability.key_arns["observability"]
  storage_class_name = module.eks_addons.default_storage_class

  alertmanager_slack_webhook_secret_arn = module.secrets_manager_observability.external_credential_secret_arns["alertmanager-slack-webhook"]
  alertmanager_pagerduty_key_secret_arn = module.secrets_manager_observability.external_credential_secret_arns["alertmanager-pagerduty-key"]
  secrets_manager_path_prefix           = module.secrets_manager_observability.secrets_path_prefix

  prometheus_replicas     = local.observability.prometheus_replicas
  prometheus_retention    = local.observability.prometheus_retention
  prometheus_storage_size = local.observability.prometheus_storage_size
  alertmanager_replicas   = local.observability.alertmanager_replicas
  grafana_replicas        = local.observability.grafana_replicas
  loki_deployment_mode    = local.observability.loki_deployment_mode
  loki_retention_days     = local.observability.loki_retention_days
  tempo_retention_hours   = local.observability.tempo_retention_hours
  otel_sampling_ratio     = local.observability.otel_sampling_ratio

  depends_on = [module.eks_addons]
}

# ArgoCD — the deployment engine (bootstrap -> platform -> infrastructure -> applications).
# See modules/argocd's README for the full ownership-boundary rationale.
module "secrets_manager_argocd" {
  source = "../../../modules/secrets-manager"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  environment = "production"
  kms_key_arn = module.kms_observability.key_arns["observability"]

  external_credential_secrets = ["argocd-repo-credentials"]
}

module "argocd" {
  source = "../../../modules/argocd"

  tags               = module.shared.tags
  name_prefix        = module.shared.name_prefix
  environment_tier   = "production"
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
  environment_tier   = "production"
  cluster_name       = data.terraform_remote_state.cluster.outputs.cluster_name
  aws_region         = var.aws_region
  storage_class_name = module.eks_addons.default_storage_class

  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.cluster.outputs.oidc_provider_url

  ecr_registry_host     = var.ecr_registry_host
  alertmanager_endpoint = module.observability.alertmanager_service_dns

  depends_on = [module.eks_addons, module.observability, module.argocd]
}
