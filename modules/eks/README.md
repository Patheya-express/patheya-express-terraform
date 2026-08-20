# modules/eks

The "cluster" stage — Amazon EKS control plane, OIDC provider, node IAM role, two managed node
groups (`system`, `application`), and EKS Access Entries. Deployed from each environment's
`cluster/` directory, one state boundary below the corresponding `platform/` directory
(`modules/eks-addons`) — see the repository root README for why cluster creation and Helm-based
addon installation cannot share one `terraform apply`.

## Design decisions

- **Two managed node groups, on-demand only.** `system` (tainted `CriticalAddonsOnly`) hosts
  cluster-critical add-ons that must never be spot-interrupted; `application` is the on-demand
  floor Karpenter's spot NodePools (`modules/eks-addons`) scale above, never the only scaling
  mechanism — see `cloud-architecture-blueprint.md` Section 3.
- **EKS Access Entries, not aws-auth.** `access_config.authentication_mode = "API"` in `main.tf`
  disables the legacy ConfigMap-based auth path entirely — every principal with cluster access is
  a Git-reviewed `access_entries` map entry, including the Terraform CI role itself (which needs
  cluster-admin-equivalent access for `platform/`'s Kubernetes/Helm resources).
- **No default public-endpoint CIDR.** `endpoint_public_access_cidrs` has no default and explicitly
  rejects `0.0.0.0/0` — see `variables.tf`.
- **Session Manager, not SSH.** No bastion, no SSH key pair anywhere — IAM-authorized,
  CloudTrail-audited node access only.
- **One node IAM role**, shared by both managed node groups and every Karpenter-provisioned node
  (`modules/eks-addons`' `EC2NodeClass` references it by name) — no meaningful permission
  difference exists between "managed node group node" and "Karpenter node," so there's no reason
  for two roles.

## Usage

```hcl
module "eks" {
  source = "../../../modules/eks"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  private_app_subnet_ids     = data.terraform_remote_state.network.outputs.private_app_subnet_ids
  eks_node_security_group_id = data.terraform_remote_state.network.outputs.eks_node_security_group_id

  kms_key_arn = module.kms.key_arns["eks-secrets"]

  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.0/24"] # your real office/VPN egress CIDR

  access_entries = {
    terraform-ci = {
      principal_arn      = data.terraform_remote_state.network.outputs.terraform_role_arn
      access_policy_arns = ["arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"]
    }
  }
}
```
