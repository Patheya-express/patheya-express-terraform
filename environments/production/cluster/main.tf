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

# Per-mode node capacity. There is no "idle" row on purpose: in idle this entire layer is
# destroyed (EKS has no stopped state) — see docs/production-lifecycle.md. Instance types never
# vary by mode; only counts do, so build exercises the same node shapes live runs.
locals {
  capacity = {
    build = {
      system_desired   = 2, system_min = 2, system_max = 2
      app_desired      = 1, app_min = 0, app_max = 2
      coredns_replicas = 2
    }
    live = {
      system_desired   = 3, system_min = 3, system_max = 3
      app_desired      = 3, app_min = 3, app_max = 10 # production's HPA ceiling (k8s/overlays/production) is the highest of the three environments — the on-demand floor + Karpenter's spot pool both need headroom to match
      coredns_replicas = 3
    }
  }[var.operating_mode]

  # The permission set's SSO-provisioned role, looked up rather than hardcoded (its name carries a
  # random suffix IAM Identity Center assigns). EKS access entries need the ARN without the
  # /aws-reserved/sso.amazonaws.com/ path.
  platform_administrator_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${one(data.aws_iam_roles.platform_administrator.names)}"
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_roles" "platform_administrator" {
  name_regex  = "^AWSReservedSSO_PlatformAdministrator_[0-9a-f]+$"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "eks" {
  source = "../../../modules/eks"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  private_app_subnet_ids     = data.terraform_remote_state.network.outputs.private_app_subnet_ids
  eks_node_security_group_id = data.terraform_remote_state.network.outputs.eks_node_security_group_id

  # Both owned by the persistent root layer (eks-persistent.tf) so they outlive this cluster.
  kms_key_arn                 = data.terraform_remote_state.network.outputs.eks_secrets_kms_key_arn
  create_cloudwatch_log_group = false

  kubernetes_version            = "1.36" # EKS default and longest standard-support runway (to 2027-08-02) as of 2026-09-28
  support_type                  = "STANDARD"
  bootstrap_self_managed_addons = false

  # Versions are EKS's default for Kubernetes 1.36 (`aws eks describe-addon-versions
  # --kubernetes-version 1.36`, 2026-09-28). vpc-cni configuration is identical to
  # modules/eks-addons' core-addons.tf; coredns keeps its system-node placement.
  managed_addons = {
    vpc-cni = {
      version        = "v1.22.4-eksbuild.3"
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      version        = "v1.36.0-eksbuild.25"
      before_compute = true
    }
    coredns = {
      version        = "v1.14.3-eksbuild.23"
      before_compute = false
      configuration_values = jsonencode({
        replicaCount = local.capacity.coredns_replicas
        tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
        nodeSelector = { "patheya-express.io/node-role" = "system" }
      })
    }
  }

  endpoint_public_access       = false                            # private-only - Tailscale subnet router (human admin) + self-hosted GitHub runner (CI/CD) both connectivity-tested and confirmed working, see admin-connectivity.tf
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs # ignored by modules/eks when endpoint_public_access = false (public_access_cidrs resolves to null either way) - kept as a pass-through, not removed, since the variable itself still exists for a possible future reversal

  system_node_desired_size = local.capacity.system_desired
  system_node_min_size     = local.capacity.system_min
  system_node_max_size     = local.capacity.system_max

  application_node_desired_size = local.capacity.app_desired
  application_node_min_size     = local.capacity.app_min
  application_node_max_size     = local.capacity.app_max

  access_entries = {
    terraform-ci = {
      principal_arn      = data.terraform_remote_state.network.outputs.terraform_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
    # Human administrators via IAM Identity Center's PlatformAdministrator permission set — the
    # same people who already hold AdministratorAccess on this account. Reached over the Tailscale
    # router (private endpoint only); no IAM user, no static credential.
    platform-administrator-sso = {
      principal_arn      = local.platform_administrator_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
  }
}

# The cluster's log group lives in the root layer; EKS finds it purely by name, so a mismatch would
# silently create an unmanaged, unencrypted group instead. Fail the plan rather than let that happen.
check "persistent_log_group_name" {
  assert {
    condition     = data.terraform_remote_state.network.outputs.eks_cluster_log_group_name == "/aws/eks/${module.eks.cluster_name}/cluster"
    error_message = "Root layer's eks_cluster_log_group_name does not match this cluster's name — EKS would log to a different, unmanaged group."
  }
}
