module "shared" {
  source = "../../modules/shared"

  environment = "shared-services"
  application = "platform"
  purpose     = "Shared services account — ECR image registry, apex Route53 zone, CI/CD runners"
  retention   = "n/a"
}

module "iam" {
  source = "../../modules/iam"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  github_repositories = ["patheya-express-terraform"]

  # The application repos' own image-push OIDC roles — added here in Phase 8 (Enterprise CI/CD
  # Platform), the phase this repository's own prior comment (see git history) deferred them to.
  # Real repo names (backend_github_repository/frontend_github_repository defaults) and the real
  # org login case (github_organization's default) were verified against the GitHub API during
  # Phase 8 — see modules/iam/variables.tf's variable descriptions for what was wrong before and
  # why it matters for OIDC trust-policy matching.
  backend_ecr_repository_arns = [module.ecr.repository_arns["api-gateway"]]
  frontend_ecr_repository_arns = [
    module.ecr.repository_arns["customer-app"],
    module.ecr.repository_arns["partner-app"],
    module.ecr.repository_arns["delivery-app"],
    module.ecr.repository_arns["admin-app"],
  ]
}

module "kms" {
  source = "../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    ecr = {
      description         = "Encrypts every ECR repository's container images"
      additional_services = ["ecr.amazonaws.com"]
    }
  }
}

module "ecr" {
  source = "../../modules/ecr"

  tags            = module.shared.tags
  kms_key_arn     = module.kms.key_arns["ecr"]
  organization_id = var.organization_id
}

# The apex zone — patheyaexpress.com itself. Every environment's own delegated subdomain zone
# (environments/{development,staging,production}) gets an NS record here — see
# route53-delegation.tf.
module "route53_apex" {
  source = "../../modules/route53"

  tags      = module.shared.tags
  zone_name = "patheyaexpress.com"
}
