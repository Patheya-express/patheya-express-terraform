# patheya-express-terraform

AWS infrastructure for Patheya Express, from account foundation through the EKS/data/observability
platform. Implements `cloud-architecture-blueprint.md` and `platform-standards.md` (both governing
documents live in the
`patheya-express-platform` backend repository's `docs/architecture/`) — read both before making any
change here; where this repository's implementation needs a decision those documents don't cover,
that's a gap to raise, not to silently invent a solution for.

## Scope

**Phase 0 remediation note**: this section previously described the repository as "Phase 2"
(foundation only) and listed EKS, Aurora, ElastiCache, ArgoCD, Karpenter, the load-balancer
controller, NGINX Ingress, External Secrets, and GitHub Actions CI/CD as explicitly not
implemented. That was stale relative to the code in this same repository, which already contains
all of them — an audit surfaced the mismatch and this section was corrected to describe what
actually exists, not what an earlier phase plan said would exist by now.

**Implemented in Terraform (written, wired, `terraform validate`-clean — see below for what "written"
does not yet mean):**

- **Foundation**: AWS Organizations (7 accounts, 3 OUs, SCPs, budgets), IAM foundation (GitHub
  OIDC, Terraform CI roles, permission boundaries — no IAM users anywhere), networking (VPC,
  subnets, NAT, Security Groups, NACLs, VPC Flow Logs), DNS (Route53 zones + delegation, ACM), ECR
  (5 repositories), KMS, CloudTrail (org-wide trail), AWS Config (compliance rules, including
  mandatory tag *detection* — see the note below), GuardDuty, Security Hub, IAM Access Analyzer.
- **Platform**: Amazon EKS (control plane, managed node groups, Karpenter), EKS add-ons (AWS Load
  Balancer Controller, NGINX Ingress, ExternalDNS, cert-manager, External Secrets Operator,
  PgBouncer, storage classes), ArgoCD (app-of-apps bootstrap, 4-layer AppProjects).
- **Data**: Aurora PostgreSQL, ElastiCache Redis, Secrets Manager, AWS Backup.
- **Security & observability**: Falco, Kyverno, Trivy Operator (supply-chain security);
  self-hosted Prometheus/Grafana/Loki/Tempo/OTel Collector; CloudWatch alarms + SNS.
- **CI**: `.github/workflows/terraform-ci.yml` — fmt/validate/plan per account, no automatic apply.

**Not yet applied to any real AWS account.** No environment in this repository has been applied —
confirmed as part of the same Phase 0 remediation pass (no AWS credentials configured in the
environment that audit ran from; every `backend.tf` still contains an unfilled
`<account-id>` placeholder). "Implemented" above means the Terraform is written and internally
consistent, not that any of it is running.

**Still genuinely incomplete, hardened, or out of scope — not stale claims, real gaps:**

- **The `dr` account and cross-account DR** — `environments/dr` doesn't exist; AWS Backup's
  cross-region copy is wired, cross-account copy is deferred until that account does.
- **AWS Config's mandatory-tag enforcement is detective, not preventive** — it flags
  non-compliant resources after creation; nothing blocks creation of one missing a tag.
- **A WAF/CDN edge** — deliberately not AWS-native (ADR-004 in the platform repo's
  `cloud-architecture-blueprint.md`: Cloudflare is the sole public edge, CDN/WAF/DDoS all included
  there, not duplicated in AWS).
- **Image signing CI** — Kyverno's cosign-verification policy is `Enforce` by default with no
  signing pipeline yet to produce a signed image; the first real deploy attempt needs that
  pipeline first, or it's rejected unconditionally.
- **Application-side changes** — the backend's Redis client is not cluster-aware; ElastiCache is
  provisioned in Redis Cluster mode in every environment. That mismatch needs resolving (either
  side) before BullMQ can be trusted against it. This is an application-repository change, not a
  Terraform one, and is out of scope for this repository to make unilaterally.
- **GitHub Actions CI/CD** — the Terraform-plan workflow above exists; the application build/test/
  deploy pipelines (image build, sign, SBOM, promotion) live in `patheya-express-platform` and
  `patheya-express-gitops`, not here.

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
