# Production lifecycle — idle / build / live

Production (account `512297269884`, `ap-south-1`) keeps its full live architecture in Terraform at
all times. What changes between operating modes is only *how much of it is running*. Nothing in
this document weakens the live architecture — three AZs, three NAT Gateways, private ECS tasks,
private Aurora/Redis, AWS WAF and every security service are the same in every mode that runs
them.

**2026-10-02 — ECS Fargate (ADR-004 as amended).** The EKS `cluster/` and Kubernetes `platform/`
layers are retired (state verified empty, directories removed) and replaced by one `app/` layer.
The semantic changes versus the EKS-era version of this document are listed explicitly under
[What changed from the EKS lifecycle](#what-changed-from-the-eks-lifecycle) — nothing was changed
silently.

## Layers

| Layer | State key | Contains |
|---|---|---|
| root | `production/terraform.tfstate` | IAM/OIDC + CI deploy roles, KMS, VPC + subnets + S3 gateway endpoint, NAT (per mode), security groups (ALB, ECS tasks, RDS Proxy, migration, Redis, Aurora), Config, GuardDuty, Security Hub, flow logs, Tailscale router (per mode), retired-EKS log group |
| data | `production/data/terraform.tfstate` | Aurora PostgreSQL (1 writer + 2 readers), RDS Proxy, ElastiCache Redis (1 primary + 1 replica, cluster mode disabled), Secrets Manager (`patheya-express/production/*`), DR backup vault |
| app | `production/app/terraform.tfstate` | ACM (ap-south-1 + us-east-1), AWS WAF, ALB, ECS cluster/services/task definitions/autoscaling, S3 + CloudFront static web, Production records in the shared-services apex zone |

Dependencies: `data` reads root; `app` reads root **and** data (task definitions reference the
data layer's secrets in every mode).

## What exists in each mode

| Layer | Resource | idle | build | live |
|---|---|---|---|---|
| root | IAM/OIDC, KMS, VPC, subnets, security groups, S3 endpoint, security services | ✅ | ✅ | ✅ |
| | NAT Gateways + EIPs + private-app default routes | — | 3 (per AZ) | 3 (per AZ) |
| | Tailscale subnet router (ASG) — admin network access only, never app traffic | 0 | 1 | 1 |
| data | Aurora, RDS Proxy, ElastiCache, secrets | ✅ once applied — never part of a stop | ✅ | ✅ |
| app | ACM, WAF, ALB, CloudFront/S3, ECS cluster, task definitions | ✅ | ✅ | ✅ |
| | ECS API service (Application Auto Scaling min/max) | 0 / 0 | 1 / 1 | 2 / 6 |
| | ECS worker service (min/max) | 0 / 0 | 1 / 1 | 1 / 3 |
| | Target-tracking autoscaling (API: CPU 50 %, 1200 req/target/min; worker: CPU 60 %; both memory 75 %) | inert | inert (min = max) | active |
| | Running-task alarms (API / worker) | none | < 1 / < 1 | < 2 / < 1 |

The mode is declared per layer in a committed `operating-mode.auto.tfvars` (root and app; the
data layer has no mode). The variable has no default, is validated, and a mode change is therefore
a reviewed Git change.

**Idle means no application traffic, not "no infrastructure":** with both services at 0 tasks the
ALB answers every request with 503, so nothing reaches the data tier. Idle also turns NAT off,
which is safe precisely because no task runs. Do not put the app layer in build/live while the
root layer is idle — tasks would have no egress (ECR API, Secrets Manager, Logs).

### Fargate capacity

Task sizes are identical in every mode (API 1 vCPU / 2 GB, worker 0.5 vCPU / 1 GB, migration
0.25 vCPU / 0.5 GB) so build exercises the exact live shapes. The live maxima are deliberately
**not** the old Kubernetes HPA ceilings (API 15, worker 12): with a 200 % rolling-deployment
ceiling those could need ~42 vCPU against the account's **30 vCPU** Fargate On-Demand quota
(`L-3032A538`). Live worst case is 6 × 1 × 2 + 3 × 0.5 × 2 + 0.25 = **15.25 vCPU** (bounds sized from the 2026-10-08 single-task load test: ~40 rps ceiling per API task); the app layer's
`fargate_peak_vcpu` output has a precondition that fails the plan if a change would exceed the
quota. Raising the maxima means raising the quota first.

### Ownership of a running service

Terraform owns the ECS infrastructure and every task-definition setting (CPU/memory, environment,
secrets, health checks, hardening). `backend-deploy-ecs.yml` (patheya-express-platform) owns only
the **image revision**: it renders each release from the family's latest ACTIVE revision and swaps
the image for a digest-pinned one, so a Terraform-side setting change ships with the next release.
Application Auto Scaling owns `desired_count` within Terraform's min/max. The services therefore
`ignore_changes = [task_definition, desired_count]` — nothing else is ignored.

## Ordering

```
first launch (data and app never applied)        stop (live|build -> idle)
  1. root   operating_mode=build|live  apply       1. app   operating_mode=idle  apply (tasks -> 0)
  2. data   apply                                  2. root  operating_mode=idle  apply (NAT off)
  3. DB bootstrap (docs/production-database-       (data is NEVER destroyed by a stop)
     bootstrap.md) — once, ever
  4. shared-services apply + registrar NS change   start (idle -> build|live)
     (docs/production-dns-cutover.md) — once       1. root  operating_mode=build|live  apply
  5. app    operating_mode=build|live  apply       2. app   operating_mode=build|live  apply
  6. backend-deploy-ecs.yml (migration + rollout)
  7. frontend-deploy-web.yml
```

## Lifecycle command safety requirements

The future `scripts/patheya-prod.sh {status | start --mode build|live | stop}` must enforce, before
any plan/apply:

1. **Account**: `aws sts get-caller-identity` account is exactly `512297269884`.
2. **Region**: `ap-south-1` for every command.
3. **Identity**: the caller ARN is `assumed-role/AWSReservedSSO_PlatformAdministrator_*` (human)
   or `patheya-production-terraform-role` (CI via GitHub OIDC) — never an IAM user or access key.
4. **Git**: clean working tree; each layer's committed `operating-mode.auto.tfvars` matches the
   requested mode (the script commits nothing itself).
5. **Terraform lock**: no active entry for the layer's state key in
   `patheya-express-terraform-locks`; Terraform's own locking stays on (never `-lock=false`).
6. **Plan allowlist**: every apply uses a saved plan; `terraform show -json` is checked so that a
   mode change may only touch — root: NAT/EIP/route/router-ASG; app: Application Auto Scaling
   targets and the running-task alarms. Nothing may be destroyed outside those. No `-target`,
   ever.
7. **Data safety**: no lifecycle command ever plans a change to the data layer. Data-layer
   destruction is a separate, individually approved operation with a final snapshot and deletion
   protection removed in a reviewed change first.
8. **Drain check** before a stop's root apply: both ECS services report 0 running tasks.
9. **Confirmation**: destructive operations require typing `patheya-production` — never y/n.
10. **Logging**: every run tees plan text, apply output and caller identity to
    `logs/lifecycle-<UTC timestamp>-<command>.log`.
11. **Failure handling**: stop at the first failed step; every step is idempotent, so recovery is
    re-running the same command. State is versioned in S3 for rollback of a corrupted state.
12. **Health gates** on start: NAT Gateways `available`; ECS services `ACTIVE` with
    running = desired; ALB target group healthy on `/api/v1/health/ready`.

## CI/CD configuration (GitHub Environments named `production`)

Both deploy roles trust only jobs in a GitHub Environment called `production` — configure that
environment with required reviewers (the manual approval gate) in both repositories.

**patheya-express-platform** — values from the app layer's `ecs_deploy_settings` output, the role
from the root layer's `backend_ecs_deploy_role_arn` output:

| Variable | Source |
|---|---|
| `PRODUCTION_ECS_DEPLOY_ROLE_ARN` | root `backend_ecs_deploy_role_arn` |
| `PRODUCTION_IMAGE_REPOSITORY_URL` | `image_repository_url` |
| `PRODUCTION_ECS_CLUSTER` | `cluster_name` |
| `PRODUCTION_ECS_API_SERVICE` / `PRODUCTION_ECS_WORKER_SERVICE` | `api_service_name` / `worker_service_name` |
| `PRODUCTION_ECS_API_TASK_FAMILY` / `PRODUCTION_ECS_WORKER_TASK_FAMILY` | `api_task_family` / `worker_task_family` |
| `PRODUCTION_ECS_MIGRATION_TASK_FAMILY` | `migration_task_family` |
| `PRODUCTION_ECS_MIGRATION_LOG_GROUP` | `migration_log_group_name` |
| `PRODUCTION_ECS_MIGRATION_SUBNET_IDS` | `migration_subnet_ids`, comma-joined |
| `PRODUCTION_ECS_MIGRATION_SECURITY_GROUP_ID` | `migration_security_group_id` |

**frontend** — `PRODUCTION_STATIC_DEPLOY_ROLE_ARN` (root `frontend_static_deploy_role_arn`),
`PRODUCTION_STATIC_SITES` (app `static_site_deploy_settings`, as JSON), and the secret
`RAZORPAY_LIVE_KEY_ID`.

## Observability

CloudWatch only: task logs (`/patheya-express/production/ecs/{api,worker,migration}`, 30 days,
KMS-encrypted), Container Insights, ECS CPU/memory alarms, running-task alarms, ALB 5xx / latency /
unhealthy-target alarms, WAF metrics and blocked/counted-request logs, all routed to the
`patheya-production-alerts-application` SNS topic (no subscriptions are created by Terraform). The
API's Prometheus `/metrics` endpoint still exists and is intentionally kept, but **nothing scrapes
it on ECS** — adding Amazon Managed Prometheus / ADOT is a separate decision.

## What changed from the EKS lifecycle

| Area | EKS-era behavior | ECS behavior | Why |
|---|---|---|---|
| Runtime layers | `cluster/` + `platform/`, destroyed in idle | one `app/` layer, never destroyed by a stop; idle = 0 tasks | Fargate and the ALB have no idle control-plane cost to avoid by destroying them; keeping the layer avoids recreating ACM/CloudFront/DNS on every start |
| Data layer in build | not deployed in build | **required in every mode the app layer exists in** | ECS tasks cannot boot without Aurora/Redis/secrets; build now runs the real application |
| GitHub runner | ECS service, 1 in build/live | removed | it existed only to reach the private EKS endpoint; deploys use AWS APIs from GitHub-hosted runners |
| Tailscale router | 1 in build/live | unchanged | admin network access only; not on any application path |
| Stop ordering | platform destroy → cluster destroy → root idle | app idle → root idle | no Kubernetes-created orphans (NLBs, EBS volumes, ENIs) to sweep |
| Access into workloads | `kubectl` via Tailscale / runner | ECS Exec (IAM-authorized) | no Kubernetes API |

## Phase B expectations for the existing root state

The root layer is already applied, so its first plan after this change is not a no-op. Expected,
reviewed changes: the EKS-only `nlb`, `eks_nodes` and EKS `redis` security groups and their rules
are **destroyed**; the ECS-topology security groups (ALB, ECS tasks, Redis-ECS, RDS Proxy,
migration) and Aurora ingress rules are **created**; the self-hosted GitHub runner (ECS cluster,
service at 0, task definition, IAM role, security group, log group, PAT secret — scheduled for
deletion with the secret's recovery window) is **destroyed**; the S3 gateway endpoint, the two CI
deploy roles and their policies are **created**; and the Terraform role / permission boundary
policies are **updated in place** (ECS, CloudFront, WAF, Application Auto Scaling, ECS Exec message
channels, the scoped cross-account DNS role assumption). Nothing in the data tier is touched, and
the retired-EKS log group (`prevent_destroy`) is retained.
