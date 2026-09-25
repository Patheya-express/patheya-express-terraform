data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "patheya-express-terraform-state-214920155808"
    key    = "staging/terraform.tfstate"
    region = "ap-south-1"
  }
}

module "shared" {
  source = "../../../modules/shared"

  environment = "staging"
  application = "eks-cluster"
  purpose     = "Staging EKS control plane and managed node groups"
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

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  system_node_desired_size = 3
  system_node_min_size     = 3
  system_node_max_size     = 3

  application_node_desired_size = 3
  application_node_min_size     = 3
  application_node_max_size     = 6

  access_entries = {
    terraform-ci = {
      principal_arn      = data.terraform_remote_state.network.outputs.terraform_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
  }
}
