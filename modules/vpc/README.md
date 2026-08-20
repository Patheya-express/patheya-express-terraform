# modules/vpc

The VPC and its subnet/routing backbone — `cloud-architecture-blueprint.md` Section 2's exact
design: 3 AZs, three subnet tiers (public / private-app / private-data), one NAT Gateway per AZ in
production, an Internet Gateway, and per-tier route tables (private-data gets no default route at
all).

Security Groups, Network ACLs, and VPC Flow Logs are **not** in this module — see `modules/networking`,
which consumes this module's outputs (`vpc_id`, subnet IDs) rather than duplicating them.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  vpc_cidr           = "10.30.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs       = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
  private_app_subnet_cidrs  = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
  private_data_subnet_cidrs = ["10.30.64.0/24", "10.30.65.0/24", "10.30.66.0/24"]

  single_nat_gateway = false # true in development/staging only
}
```

## Subnet tags for future EKS auto-discovery

Public subnets carry `kubernetes.io/role/elb = 1`, private-app subnets carry
`kubernetes.io/role/internal-elb = 1` — the AWS Load Balancer Controller (Phase 3) auto-discovers
subnets by these tags rather than needing them hand-configured later. Applied now so Phase 3 has
nothing to retrofit onto an already-live VPC.
