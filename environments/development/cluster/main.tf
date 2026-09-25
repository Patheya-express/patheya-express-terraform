# Phase 1D.2 — split into two explicit remote-state reads: "network" (VPC/subnets/security
# groups, now environments/development/network/'s own state) and "account" (IAM/Route53/Config/
# Security's state — this same account, same state bucket, just the unchanged account-root key).
# A same-account remote state read is a plain S3 read the Terraform CI role already has access to,
# unlike the cross-account reads Phase 2 deliberately avoided; see that phase's environments/
# READMEs for why cross-account remote state was skipped there.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-433985779683"
    key    = "development/network/terraform.tfstate"
    region = "ap-south-1"
  }
}

data "terraform_remote_state" "account" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-433985779683"
    key    = "development/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "development"
  application = "eks-cluster"
  purpose     = "Development EKS control plane and managed node groups"
  retention   = "n/a"
}

module "kms" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    eks-secrets = {
      description         = "Envelope-encrypts Kubernetes Secrets objects for this cluster"
      additional_services = []
      key_administrators  = [data.terraform_remote_state.account.outputs.terraform_role_arn]
    }
  }
}

module "eks" {
  source = "../../../modules/eks"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  private_app_subnet_ids     = data.terraform_remote_state.network.outputs.private_app_subnet_ids
  eks_node_security_group_id = data.terraform_remote_state.network.outputs.eks_node_security_group_id

  kms_key_arn = module.kms.key_arns["eks-secrets"]

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  system_node_desired_size = 3
  system_node_min_size     = 3
  system_node_max_size     = 3

  application_node_desired_size = 2 # smaller on-demand floor than staging/production — development's HPA minReplicas are already lower (k8s/overlays/development)
  application_node_min_size     = 2
  application_node_max_size     = 4

  access_entries = {
    terraform-ci = {
      principal_arn      = data.terraform_remote_state.account.outputs.terraform_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
    # IAM Identity Center human access entries (PlatformAdministrator/Developer/ReadOnly/
    # SecurityAuditor -> matching EKS access policies) are added once Phase 2's
    # enable_identity_center is flipped on (modules/organizations README) — not fabricated here
    # against a Identity Center instance that doesn't exist yet.
  }
}
