# modules/networking

Security Groups, the private-data tier's Network ACL, and VPC Flow Logs — everything in
`cloud-architecture-blueprint.md` Section 2's "Security Groups (stateful, primary enforcement
layer)" and "Network ACLs (stateless, defense-in-depth)" subsections, plus flow logging.

Consumes `modules/vpc`'s outputs rather than creating its own VPC/subnets — this module answers
"who can talk to whom," `modules/vpc` answers "what exists and how is it routed."

## Security Groups created now, attached later

`eks-node-sg`, `aurora-sg`, and `redis-sg` are created in this phase even though EKS/Aurora/Redis
themselves are explicitly out of scope (see the repository root `README.md`) — a Security Group is
a free ACL object; defining the network policy now means Phase 3/4 attaches to an already-reviewed
boundary instead of inventing one under deploy pressure. Contrast this with `modules/kms`, which
deliberately does NOT pre-create Aurora/Redis keys — a KMS key is a real, distinctly-billed,
independently-manageable resource, not a policy object with no cost implication either way.

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_id                   = module.vpc.vpc_id
  vpc_cidr                 = module.vpc.vpc_cidr
  private_app_subnet_ids   = module.vpc.private_app_subnet_ids
  private_data_subnet_ids  = module.vpc.private_data_subnet_ids

  flow_log_kms_key_arn = module.kms.key_arns["cloudtrail-logs"] # or a dedicated "vpc-flow-logs" key, if flow-log volume warrants a separate key later
}
```
