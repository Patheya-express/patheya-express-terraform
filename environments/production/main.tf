module "shared" {
  source = "../../modules/shared"

  environment = "production"
  application = "platform"
  purpose     = "Production environment — customer-facing, manual-approval-gated deploys only"
  retention   = "365-days"
}

# Per-mode runtime capacity for this layer — explicit values, one row per mode, no derived math.
# The NAT topology itself (single_nat_gateway below) never varies by mode.
# NAT is the ECS tasks' egress path (ECR via S3 endpoint excepted): Cloudinary, Razorpay, SMTP,
# Secrets Manager, CloudWatch Logs, ECR API.
locals {
  runtime = {
    idle  = { nat_gateways = false, tailscale_router = 0 }
    build = { nat_gateways = true, tailscale_router = 1 }
    live  = { nat_gateways = true, tailscale_router = 1 }
  }[var.operating_mode]

  # ECS naming contract. The app layer (environments/production/app) creates these resources and
  # asserts, in a check block, that its module outputs still match; this layer needs them first
  # because the CI deploy roles below are scoped to them and this layer is applied before app/.
  ecs_contract = {
    cluster_name             = "${module.shared.name_prefix}-ecs"
    api_service_name         = "${module.shared.name_prefix}-api"
    worker_service_name      = "${module.shared.name_prefix}-worker"
    migration_task_family    = "${module.shared.name_prefix}-migration"
    migration_log_group_name = "/patheya-express/production/ecs/migration"
    pass_role_names = [
      "${module.shared.name_prefix}-ecs-execution-role",
      "${module.shared.name_prefix}-ecs-api-task-role",
      "${module.shared.name_prefix}-ecs-worker-task-role",
      "${module.shared.name_prefix}-ecs-migration-task-role",
    ]
  }

  # modules/static-site's bucket naming: <name_prefix>-<site>-frontend-<account-id>.
  static_site_bucket_names = [
    for site in var.static_sites :
    "${module.shared.name_prefix}-${site}-frontend-${data.aws_caller_identity.current.account_id}"
  ]

  shared_services_api_gateway_repository_arn = "arn:aws:ecr:${var.aws_region}:${var.shared_services_account_id}:repository/patheya-express/api-gateway"
  shared_services_production_dns_role_arn    = "arn:aws:iam::${var.shared_services_account_id}:role/patheya-shared-services-production-dns-records-role"
}

data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  # Production runs the ECS Fargate API/worker behind an ALB, ECS service autoscaling, CloudFront
  # static web, the API WAF and ECS Exec (modules/ecs enable_execute_command) — every family enabled.
  workload_permissions = {
    ecs                               = true
    application_autoscaling           = true
    cloudfront                        = true
    wafv2                             = true
    ecs_exec                          = true
    load_balancer_service_linked_role = true
  }

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  # Manual-approval-gated (platform-standards.md Section 6) — restricting to `main` (the module
  # default) is necessary but not sufficient on its own; the GitHub Actions workflow's own
  # environment-protection-rule (a manual reviewer gate on the "production" GitHub Environment)
  # is what actually enforces the approval step.

  # The app layer writes Production's records into the shared-services apex zone through this role.
  cross_account_assume_role_arns = [local.shared_services_production_dns_role_arn]

  # Application deploy roles — CI owns the ECS task-definition revision and the static files;
  # Terraform owns everything else. Both trust only the "production" GitHub Environment.
  ecs_deploy = {
    github_environment       = "production"
    cluster_name             = local.ecs_contract.cluster_name
    service_names            = [local.ecs_contract.api_service_name, local.ecs_contract.worker_service_name]
    migration_task_family    = local.ecs_contract.migration_task_family
    migration_log_group_name = local.ecs_contract.migration_log_group_name
    pass_role_names          = local.ecs_contract.pass_role_names
    image_repository_arn     = local.shared_services_api_gateway_repository_arn
  }

  static_site_deploy = {
    github_environment = "production"
    bucket_names       = local.static_site_bucket_names
    environment_tag    = "production"
  }
}

module "kms" {
  source = "../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    cloudtrail-logs = {
      description         = "Encrypts this account's VPC Flow Logs, Config snapshots, and its security-findings SNS topic"
      additional_services = ["cloudtrail.amazonaws.com", "logs.amazonaws.com", "config.amazonaws.com", "delivery.logs.amazonaws.com", "sns.amazonaws.com", "events.amazonaws.com"]
    }
    admin-connectivity = {
      description         = "Encrypts the Tailscale router's auth-key secret, the GitHub runner's PAT secret, and the runner's CloudWatch log group - see admin-connectivity.tf"
      additional_services = ["logs.amazonaws.com"]
    }
    # Retained only because it encrypts the retired EKS cluster's persistent control-plane log
    # group (eks-persistent.tf, prevent_destroy) — EKS is no longer part of Production's target
    # architecture. Remove together with that log group once its retention has lapsed.
    eks-secrets = {
      description         = "Envelope-encrypts the Production EKS cluster's Kubernetes Secrets and its persistent control-plane log group - see eks-persistent.tf"
      additional_services = ["eks.amazonaws.com", "logs.amazonaws.com"]
      key_administrators  = [module.iam.terraform_role_arn]
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_cidr           = "10.30.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs       = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
  private_app_subnet_cidrs  = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
  private_data_subnet_cidrs = ["10.30.64.0/24", "10.30.65.0/24", "10.30.66.0/24"]

  single_nat_gateway = true                       # pre-launch cost optimization (2026-10-08): one NAT (ap-south-1a) serves all three private-app subnets; set back to false (one per AZ, cloud-architecture-blueprint.md Section 2) before production traffic
  enable_nat_gateway = local.runtime.nat_gateways # off only in idle mode — nothing in private-app needs egress then
}

module "networking" {
  source = "../../modules/networking"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  private_data_subnet_ids = module.vpc.private_data_subnet_ids

  flow_log_kms_key_arn    = module.kms.key_arns["cloudtrail-logs"]
  flow_log_retention_days = 30

  # ECS Fargate runtime (ADR-004 as amended): no EKS node/NLB security groups at all.
  create_eks_topology_security_groups = false

  create_ecs_topology_security_groups = true
  ecs_database_target                 = "aurora" # API/worker -> RDS Proxy -> Aurora; migration task -> Aurora writer
  ecs_api_container_port              = 3000

  # The ALB is the public edge — reachable from anywhere, protected by AWS WAF (app layer).
  # Port 80 exists only for the HTTP -> HTTPS redirect.
  alb_allowed_cidrs         = ["0.0.0.0/0"]
  alb_http_redirect_ingress = true
}

# No route53 module call here, deliberately: production is the ONE environment that uses the apex
# zone (patheyaexpress.com, environments/shared-services) directly rather than a delegated
# subdomain — platform-standards.md Section 6: "production has no environment prefix." The app
# layer manages Production's own records in that zone through the shared-services
# production-dns-records role (environments/shared-services/production-dns.tf).

module "config" {
  source = "../../modules/config"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]
}

module "security" {
  source = "../../modules/security"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix
  kms_key_arn = module.kms.key_arns["cloudtrail-logs"]

  finding_notification_emails = var.security_finding_notification_emails
}
