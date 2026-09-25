data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-512297269884"
    key    = "production/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "production"
  application = "eks-cluster"
  purpose     = "Production EKS control plane and managed node groups"
  retention   = "n/a"
}

module "kms" {
  source = "../../../modules/kms"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  keys = {
    eks-secrets = {
      description = "Envelope-encrypts Kubernetes Secrets objects for this cluster"
      # eks.amazonaws.com: EKS's own encryption_config (Kubernetes Secrets envelope encryption)
      # uses this key directly. logs.amazonaws.com: this same key also encrypts the cluster's
      # CloudWatch log group (modules/eks/main.tf's aws_cloudwatch_log_group.cluster) - confirmed
      # required the hard way: an apply against additional_services = [] failed with
      # AccessDeniedException creating that log group.
      additional_services = ["eks.amazonaws.com", "logs.amazonaws.com"]
      key_administrators  = [data.terraform_remote_state.network.outputs.terraform_role_arn]
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

  endpoint_public_access       = false                            # private-only - Tailscale subnet router (human admin) + self-hosted GitHub runner (CI/CD) both connectivity-tested and confirmed working, see admin-connectivity.tf
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs # ignored by modules/eks when endpoint_public_access = false (public_access_cidrs resolves to null either way) - kept as a pass-through, not removed, since the variable itself still exists for a possible future reversal

  system_node_desired_size = 3
  system_node_min_size     = 3
  system_node_max_size     = 3

  application_node_desired_size = 3
  application_node_min_size     = 3
  application_node_max_size     = 10 # production's HPA ceiling (k8s/overlays/production) is the highest of the three environments — the on-demand floor + Karpenter's spot pool both need headroom to match

  access_entries = {
    terraform-ci = {
      principal_arn      = data.terraform_remote_state.network.outputs.terraform_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
  }
}
