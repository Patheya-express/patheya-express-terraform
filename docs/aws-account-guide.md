# AWS account guide

Seven accounts under one AWS Organization, three OUs — see `modules/organizations/README.md` for
the resource-level detail and manual prerequisites. This page is the quick-reference table.

| Account | OU | Owns | Environment/singleton created by |
| --- | --- | --- | --- |
| management | (org root) | The Organization itself, IAM Identity Center, org-wide CloudTrail trail resource | `environments/management` |
| security | Security | CloudTrail log archive, GuardDuty/Security Hub org delegation, org-wide Config aggregator + Access Analyzer | `environments/security` |
| shared-services | Infrastructure | ECR (all 5 app images), the apex Route53 zone | `environments/shared-services` |
| development | Workloads | Dev VPC/EKS (Phase 3)/data (Phase 4) | `environments/development` |
| staging | Workloads | Staging VPC/EKS/data | `environments/staging` |
| production | Workloads | Production VPC/EKS/data | `environments/production` |
| dr | Workloads | Pilot-light DR resources | **Not built in this phase** — see root README |

SCPs (`modules/organizations/scps.tf`): baseline (deny-leave-org, deny-root-user) apply to every
OU; region restriction, IMDSv2 enforcement, and security-service tamper protection apply to
Workloads (and, for tamper protection, Infrastructure) — never to Security, which needs to
administer those services.

Budgets: one per member account (`modules/organizations/budgets.tf`), alerting at 50/80/100% of
the `cloud-architecture-blueprint.md` Section 13 growth-tier estimate for each account.
