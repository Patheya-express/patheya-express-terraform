# Human administrator network access to the private-app tier.
#
# Production's runtime is ECS Fargate (ADR-004 as amended). Operational access INTO running tasks is
# ECS Exec (modules/ecs enable_execute_command, IAM-authorized, session-logged), and CI/CD reaches
# ECS purely through AWS APIs from GitHub-hosted runners — no private Kubernetes endpoint exists
# any more, so the self-hosted GitHub runner and the EKS security-group rules that served it have
# been removed from this layer.
#
# The Tailscale subnet router below is unchanged: it is not on any application traffic path, it
# advertises only the private-app subnet CIDRs (never the private-data tier, so no tailnet device
# can reach Aurora/Redis), and it scales to 0 in idle mode.

module "tailscale_router" {
  source = "../../modules/tailscale-router"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  permission_boundary_arn = module.iam.permission_boundary_arn
  kms_key_arn             = module.kms.key_arns["admin-connectivity"]

  # The exact 3 private-app subnet CIDRs from this root's own module.vpc call above - never the
  # whole 10.30.0.0/16 VPC CIDR, which would also expose the private-data tier.
  advertised_route_cidrs = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]

  desired_capacity = local.runtime.tailscale_router # 0 in idle - no NAT for it to reach Tailscale through
}
