# patheya-express-terraform

AWS infrastructure for Patheya Express, from account foundation through the Production ECS
Fargate runtime. Implements `cloud-architecture-blueprint.md` and `platform-standards.md` (both
governing documents live in the `patheya-express-platform` backend repository's
`docs/architecture/`) — read both before making any change here; where this repository's
implementation needs a decision those documents don't cover, that's a gap to raise, not to
silently invent a solution for.

## Where each environment runs

| Environment | Hosting | In this repository |
|---|---|---|
| **Production** | **AWS** — account `512297269884`, `ap-south-1` | `environments/production` (root, `data/`, `app/`) |
| Development / QA / Staging | **Not AWS** — Render, Neon, Upstash, Vercel | AWS account baselines only (`environments/development`, `qa`, `staging` hold no application runtime) |
| Shared services | AWS — `668506406019` | ECR (`api-gateway`), apex Route53 zone, Production DNS-records role |
| Management / Security | AWS | Organizations, Identity Center, CloudTrail, Config, GuardDuty, Security Hub |

## Production architecture (ADR-004 as amended, 2026-10-02)

```
Capacitor mobile apps (primary)            Admin / secondary web (browser)
        │ HTTPS api.patheyaexpress.com             │ HTTPS admin./customer./restaurant./delivery.
        ▼                                          ▼
  AWS WAF ─► public ALB (ACM, TLS 1.3)       CloudFront (ACM us-east-1, OAC) ─► private S3
        │ :3000, private-app subnets                │ (static files call the API above)
        ▼
  ECS Fargate API service ◄─ Socket.IO Redis adapter ─► ECS Fargate worker service (BullMQ)
        │                                                   │
        ├──► RDS Proxy ─► Aurora PostgreSQL  (private-data) ◄┘   one-off migration task ─► Aurora writer
        ├──► ElastiCache Redis, cluster mode disabled, TLS + AUTH (private-data)
        └──► Cloudinary / Razorpay / SMTP via NAT (one per AZ)
```

Layers (`docs/production-lifecycle.md`): **root** (VPC, security groups, IAM/OIDC, CI deploy
roles, security services) -> **data** (Aurora, RDS Proxy, ElastiCache, Secrets Manager) ->
**app** (ACM, WAF, ALB, ECS, S3/CloudFront, Production DNS records). The former `cluster/` (EKS)
and `platform/` (Kubernetes add-ons, ArgoCD, in-cluster observability and supply-chain tooling)
layers are retired: their state was verified empty and their directories removed. The
EKS/Kubernetes modules remain in `modules/` only because the Development/Staging EKS roots still
reference them.

## Scope

**What is live in AWS** (verified read-only on 2026-10-02): the AWS Organization and IAM Identity
Center (management account), the organization CloudTrail, and the **Production root layer** —
VPC, nine subnets, security groups, IAM/GitHub OIDC, KMS, Config, GuardDuty, Security Hub,
Access Analyzer, flow logs — in `idle` mode (no NAT Gateways), with state in
`patheya-express-terraform-state-512297269884`. Production's `data/` and `app/` layers have never
been applied (no state), and shared-services has no ECR repository or Route53 zone yet. The
statement this README previously made — "not yet applied to any real AWS account" — is no longer
true and has been removed. Every first apply of the remaining layers is a reviewed, approved step
(`docs/production-lifecycle.md`).

**Implemented in Terraform:**

- **Foundation**: AWS Organizations (7 accounts, 3 OUs, SCPs, budgets), IAM foundation (GitHub
  OIDC, Terraform CI roles, permission boundaries — no IAM users anywhere), networking (VPC,
  subnets, NAT, Security Groups, NACLs, VPC Flow Logs, S3 gateway endpoint), DNS (Route53 zones,
  ACM), ECR, KMS, CloudTrail (org-wide trail), AWS Config, GuardDuty, Security Hub, IAM Access
  Analyzer.
- **Production runtime**: ECS Fargate (API + worker services, one-off migration task, Application
  Auto Scaling, ECS Exec, Container Insights, read-only root filesystem), ALB with access logs and
  deletion protection, AWS WAF (`modules/waf`), S3 + CloudFront static web (`modules/static-site`).
- **Data**: Aurora PostgreSQL, RDS Proxy (`modules/rds-proxy`), ElastiCache Redis (cluster mode
  disabled), Secrets Manager, AWS Backup with a DR-region vault.
- **CI**: `.github/workflows/terraform-ci.yml` — fmt/validate/plan per account, no automatic apply.
  Application deploys are separate GitHub OIDC roles in Production (`modules/iam`), used by
  `patheya-express-platform`'s `backend-deploy-ecs.yml` and the frontend's
  `frontend-deploy-web.yml`.

**Still genuinely incomplete, hardened, or out of scope — real gaps:**

- **The `dr` account and cross-account DR** — `environments/dr` doesn't exist; AWS Backup's
  cross-region copy is wired, cross-account copy is deferred until that account does.
- **AWS Config's mandatory-tag enforcement is detective, not preventive** — it flags
  non-compliant resources after creation; nothing blocks creation of one missing a tag.
- **Prometheus metrics are not scraped in Production.** The API exposes `/metrics` (Prometheus
  format) and it is intentionally kept, but ECS has no scraper: Production observability is
  CloudWatch (task logs, Container Insights, ECS/ALB/WAF metrics and alarms). Adding Amazon
  Managed Prometheus / ADOT is a separate, future decision.
- **Production database roles** — `patheya_app` / `patheya_migrator` are created by a one-time,
  documented privileged bootstrap (`docs/production-database-bootstrap.md`), not by Terraform.
- **DNS cutover** — `patheyaexpress.com` is still on the registrar's parking nameservers; moving it
  to the shared-services Route53 zone is a manual registrar step
  (`docs/production-dns-cutover.md`).

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
    ecs/                  # ECS Fargate cluster, API/worker services, migration task, autoscaling
    alb/                  # public ALB, HTTPS listener, access logs, WAF association
    waf/                  # regional AWS WAFv2 web ACL (AWS managed rule groups)
    rds-proxy/            # RDS Proxy in front of Aurora PostgreSQL
    static-site/          # private S3 + CloudFront (OAC) static web hosting
    cloudtrail/            # organization-wide trail (split: management owns the trail, security owns the bucket)
    config/                # AWS Config recorder/rules/aggregator
    security/              # GuardDuty, Security Hub, IAM Access Analyzer
  environments/
    management/            # the org's management account
    security/               # log archive + security-service delegated admin
    shared-services/        # ECR + apex Route53 zone + Production DNS-records role
    development/
    staging/
    production/             # root (network, IAM, security services)
      data/                 # Aurora, RDS Proxy, ElastiCache, Secrets Manager
      app/                  # ACM, WAF, ALB, ECS, S3/CloudFront, Production DNS records
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

`environments/dr` (the disaster-recovery account) is **not** built out — a real, current gap, not
a stale phase-ordering note: the EKS/data-layer work it would protect already exists (see Scope
above), but the `patheya-dr` account itself has never been created, so AWS Backup's cross-region
copy has no cross-account destination yet. See `docs/backup-guide.md`.

## Getting started

Read `docs/bootstrap-guide.md` — it is the literal, ordered sequence every account must be deployed
in, including the manual steps Terraform cannot do (creating the management account itself,
enabling IAM Identity Center, cross-account role assumption for each new member account's first
bootstrap).

## Validation

`terraform fmt -recursive` and `terraform validate` (per module, with `-backend=false`) are run in
CI on every PR (`.pre-commit-config.yaml` runs the same checks locally, first) via
`.github/workflows/terraform-ci.yml`, which also runs `terraform plan` (never `apply`) per account
against that account's own Terraform CI role (`modules/iam`), using the reusable workflow in
`patheya-express-platform`. No job in this repository's own CI runs `apply` — a human with real,
appropriately-scoped account access is the only path to `apply`, same as `docs/bootstrap-guide.md`
describes for the initial bootstrap of each account.

## Standards

Naming, tagging, Git, and every other cross-cutting convention used throughout this repository come
from `platform-standards.md` — this repository doesn't redefine them locally.
