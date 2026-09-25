# Private EKS control-plane access - two independent paths, neither requiring
# endpoint_public_access_cidrs (module.eks's cluster call, in cluster/main.tf, still hardcodes
# endpoint_public_access = true today; flipping it to false is a deliberate, separate change made
# only after both paths below are deployed and verified reachable - see docs/bootstrap-guide.md and
# this change's own design notes).
#
# 1. Human administrators: modules/tailscale-router - a subnet router advertising only the
#    private-app subnet CIDRs (where the EKS control-plane ENIs live), never the whole VPC CIDR,
#    so a tailnet-connected device can reach the EKS API but not Aurora/Redis.
# 2. CI/CD (GitHub Actions / Terraform platform-layer applies): modules/github-runner - a
#    self-hosted runner inside this same VPC, needing no Tailscale at all since it already has
#    ordinary VPC-internal reachability. Still authenticates to AWS via the existing GitHub OIDC ->
#    module.iam.aws_iam_role.terraform assumption - this changes network placement only, not IAM.

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
}

module "github_runner" {
  source = "../../modules/github-runner"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                  = module.vpc.vpc_id
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  permission_boundary_arn = module.iam.permission_boundary_arn
  kms_key_arn             = module.kms.key_arns["admin-connectivity"]
}

# SG-to-SG ingress on the existing eks_nodes security group (module.networking) - not modifying
# modules/networking itself, since that module is shared by every environment and this rule is
# Production-specific. Each new module's own security group is the referenced principal, never a
# hardcoded CIDR.

resource "aws_vpc_security_group_ingress_rule" "eks_from_tailscale_router" {
  security_group_id            = module.networking.eks_node_security_group_id
  description                  = "EKS API (private endpoint) from the Tailscale subnet router - human administrator path."
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = module.tailscale_router.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_github_runner" {
  security_group_id            = module.networking.eks_node_security_group_id
  description                  = "EKS API (private endpoint) from the self-hosted GitHub Actions runner - CI/CD path."
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = module.github_runner.security_group_id
}
