# patheya-express-terraform

AWS Foundation for Patheya Express — Phase 2 of the platform's infrastructure buildout. Implements
`cloud-architecture-blueprint.md` and `platform-standards.md` (both governing documents live in the
`patheya-express-platform` backend repository's `docs/architecture/`) — read both before making any
change here; where this repository's implementation needs a decision those documents don't cover,
that's a gap to raise, not to silently invent a solution for.

## Scope of this phase

**Implemented:** AWS Organizations (7 accounts, 3 OUs, SCPs, budgets), IAM foundation (GitHub OIDC,
Terraform CI roles, permission boundaries — no IAM users anywhere), networking (VPC, subnets,
NAT, Security Groups, NACLs, VPC Flow Logs), DNS (Route53 zones + delegation, ACM), ECR (5
repositories), KMS, CloudTrail (org-wide trail), AWS Config (compliance rules, including mandatory
tag enforcement), GuardDuty, Security Hub, IAM Access Analyzer.

**Explicitly not implemented — later phases:** Amazon EKS, Aurora PostgreSQL, ElastiCache Redis,
External Secrets, ArgoCD, Karpenter, AWS Load Balancer Controller, NGINX Ingress, application
workloads, GitHub Actions CI/CD, BullMQ, Socket.IO. This phase prepares the AWS foundation those
land on; it deploys none of them.

## Repository structure

```
patheya-express-terraform/
  bootstrap/              # creates the S3 state bucket + DynamoDB lock table — LOCAL state, run once per account, first
  modules/
    shared/               # tagging + naming locals, consumed by every other module
    organizations/        # AWS Organizations, OUs, member accounts, SCPs, budgets, IAM Identity Center (gated)
    iam/                  # GitHub OIDC, Terraform CI role, permission boundary
    kms/                  # per-data-class customer-managed keys
    vpc/                  # VPC, subnets, IGW, NAT, route tables
    networking/           # Security Groups, private-data NACL, VPC Flow Logs
    route53/               # hosted zones + DNS-validated wildcard ACM certificates
    ecr/                  # container image repositories
    cloudtrail/            # organization-wide trail (split: management owns the trail, security owns the bucket)
    config/                # AWS Config recorder/rules/aggregator
    security/              # GuardDuty, Security Hub, IAM Access Analyzer
  environments/
    management/            # the org's management account
    security/               # log archive + security-service delegated admin
    shared-services/        # ECR + apex Route53 zone
    development/
    staging/
    production/
  docs/
```

**Two structural additions beyond what Phase 2's task brief explicitly listed under `modules/`**,
both documented rather than silently folded elsewhere:

1. **`modules/organizations`** — the brief's `modules/` list didn't name an explicit module for
   AWS Organizations/Accounts/SCPs/IAM Identity Center, even though Section 2 of that brief
   requires all four. See `modules/organizations/README.md`.
2. **`environments/security` and `environments/shared-services`** — the brief's `environments/`
   list named only `development`/`staging`/`production`. AWS Organizations, CloudTrail's
   separation-of-duties design, ECR, and the apex Route53 zone all need a home that isn't any of
   those three (nor is it a per-environment concern) — see `docs/aws-account-guide.md`.

`environments/dr` (the disaster-recovery account) is **not** built out in this phase — the
blueprint's pilot-light DR strategy means it's built alongside Phase 3/4's EKS/data-layer work, not
ahead of having anything to protect.

## Getting started

Read `docs/bootstrap-guide.md` — it is the literal, ordered sequence every account must be deployed
in, including the manual steps Terraform cannot do (creating the management account itself,
enabling IAM Identity Center, cross-account role assumption for each new member account's first
bootstrap).

## Validation

`terraform fmt -recursive` and `terraform validate` (per module, with `-backend=false`) are run in
CI on every PR (`.pre-commit-config.yaml` runs the same checks locally, first). `terraform plan`
against real AWS credentials is **not** run by anyone other than a human with real,
appropriately-scoped account access — see `docs/bootstrap-guide.md`; this repository does not
assume or grant blanket plan/apply access to any automated process until Phase 7 wires up the
GitHub Actions workflows that use the Terraform CI roles `modules/iam` already creates.

## Standards

Naming, tagging, Git, and every other cross-cutting convention used throughout this repository come
from `platform-standards.md` — this repository doesn't redefine them locally.
