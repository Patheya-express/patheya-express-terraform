# CI baseline and Checkov remediation backlog

Recorded 2026-10-09, when the reconciliation stack (PRs #3–#9) was merged. `terraform-ci.yml`
runs the reusable plan workflow from `patheya-express-platform` (fmt, validate, tflint, tfsec,
Checkov hard-fail, plan) on every pull request to `main` and every push to `main`.

## Inherited CI baseline

`main` at a4aeca7 and PR #3 fail the same 38 of 43–47 checks. None is a `terraform validate`
failure — validate passes in every module job.

| Group | Jobs | Failing step | Cause |
|---|---|---|---|
| Environment plans | 15 | Configure AWS credentials (OIDC) | No `TF_ROLE_ARN_*` repository secrets / CI roles yet. The job stops before validate, tflint, Checkov and plan, so environment roots have never been scanned in CI. |
| Module validation | 16 | tflint | `terraform_unused_declarations` (26 findings). |
| Module validation | 7 | Checkov | Findings listed below (hard fail, no skip list). |

After the stack:

- **tflint** — the 18 findings in retained modules were removed (commit "Remove declarations
  tflint reports as unused"); the other 8 were in modules the four-account scope deleted. A local
  run (tflint v0.53.0, CI's invocation: from the module directory, no plugins) is clean for every
  module and retained root except `environments/development` (decommission-only, no CI job):
  one unused `terraform_remote_state.network`.
- **Plans** — CI keeps failing at OIDC until least-privilege CI roles exist in the four approved
  accounts and their ARNs are stored as repository secrets. Plan-development and plan-staging jobs
  were removed with the four-account scope.
- **Checkov** — still fails; tracked below rather than suppressed.

## Checkov backlog

Scan of the stack tip (checkov 3.3.26, `--framework terraform`, each module and retained root):
224 findings across 45 checks. Scanning a module in isolation evaluates variable defaults, and
`count`-indexed resources confuse several graph checks, so findings were verified against the
live accounts before triage.

### Verified false positives (live state already compliant)

| Check | Finding | Live evidence (2026-10-09) |
|---|---|---|
| CKV_AWS_7 | KMS rotation | All 7 enabled customer-managed keys in Production: rotation on. |
| CKV2_AWS_11 | VPC flow logs | Production VPC: flow log ALL → CloudWatch Logs, ACTIVE. |
| CKV_AWS_192, CKV2_AWS_76 | WAF Log4j rule | API web ACL includes AWSManagedRulesKnownBadInputsRuleSet. |
| CKV2_AWS_6 | S3 public access block | Every bucket in Production and Security blocks all four public settings. |
| CKV_AWS_150, CKV_AWS_91 | ALB deletion protection / access logs | Both enabled on `patheya-production-alb`. |

### Real gaps — remediate (none blocks the deployment)

| Priority | Check | Gap | Proposed fix |
|---|---|---|---|
| Medium | CKV2_AWS_32 | The four CloudFront web distributions have no response-headers policy: no HSTS, `X-Frame-Options`, `X-Content-Type-Options` on the frontends. | AWS managed `SecurityHeadersPolicy` (or a custom one with a CSP) in `modules/static-site`. |
| Medium | CKV2_AWS_12 | Production VPC default security group keeps the AWS default rules (self-ingress, all egress). Nothing should use it. | `aws_default_security_group` with no rules in `modules/vpc`. |
| Medium | CKV2_AWS_57 | Database credentials in Secrets Manager do not rotate. External app secrets (Razorpay, SMTP, Cloudinary) are provider-issued and rotated manually. | Rotation for the app/migrator DB users via RDS Proxy-compatible rotation; `bank-account-encryption-key` must never rotate. |
| Low | CKV_AWS_68, CKV_AWS_374, CKV2_AWS_47 | CloudFront distributions have no WAF / geo restriction. Static content only; the API is behind the ALB WAF. | Optional CloudFront WAF (us-east-1) if abuse appears. |
| Low | CKV_AWS_336 | ECS containers have a writable root filesystem. | `readonlyRootFilesystem` + tmpfs for writable paths after testing the app. |
| Low | CKV_AWS_65 | ECS Container Insights off (cost decision). | Enable when the live baseline justifies the cost. |

### Accepted by design

| Checks | Reason |
|---|---|
| CKV_AWS_356, CKV_AWS_111, CKV_AWS_109, CKV_AWS_108, CKV_AWS_107 | Terraform CI role and permission boundary use service wildcards by design, scoped per account by `workload_permissions` and the boundary. |
| CKV_AWS_274 | Identity Center `PlatformAdministrator` permission set (break-glass, federated, no static keys). |
| CKV_AWS_144, CKV2_AWS_62, CKV_AWS_18, CKV2_AWS_61, CKV_AWS_300, CKV_AWS_21, CKV_AWS_145 | S3 replication, event notifications, access logging, lifecycle and SSE-KMS on log/state/static buckets: cost/benefit not justified pre-launch; revisit with the DR plan. |
| CKV_AWS_338 | Log retention below one year: chosen per log group for cost. |
| CKV_AWS_162, CKV_AWS_161, CKV2_AWS_27, CKV_AWS_226 | Aurora uses RDS Proxy with Secrets Manager auth; query logging and automatic minor upgrades are operational choices. |
| CKV2_AWS_5 | Security groups referenced across layers (data/app) — attached in another state. |
| CKV2_AWS_3, CKV_AWS_252, CKV2_AWS_10, CKV_AWS_35, CKV2_AWS_38, CKV2_AWS_39 | GuardDuty is org-wide from the delegated admin; CloudTrail/Route 53 logging choices made in the security account design. |
| modules/rds, modules/observability, modules/supply-chain-security | No caller in a retained root; findings there are inert until the module is used. |

### All findings at the stack tip

| Check | Description | Count | Where (count) |
|---|---|---|---|
| CKV2_AWS_5 | Ensure that Security Groups are attached to another resource | 20 | modules/networking(10) environments/production(10) |
| CKV2_AWS_57 | Ensure Secrets Manager secrets should have automatic rotation enabled | 17 | modules/observability(1) environments/production/data(11) modules/rds(1) modules/tailscale-router(1) modules/secrets-manager(2) environments/production(1) |
| CKV_AWS_144 | Ensure that S3 bucket has cross-region replication enabled | 16 | environments/production(1) modules/cloudtrail(2) modules/alb(1) environments/management(3) modules/config(1) environments/security(3) modules/static-site(1) environments/production/app(2) modules/observability(2) |
| CKV2_AWS_62 | Ensure S3 buckets should have event notifications enabled | 16 | environments/production(1) environments/management(3) modules/cloudtrail(2) modules/alb(1) modules/config(1) environments/security(3) environments/production/app(2) modules/static-site(1) modules/observability(2) |
| CKV_AWS_338 | Ensure CloudWatch log groups retains logs for at least 1 year | 13 | modules/cloudtrail(1) environments/management(1) modules/networking(1) environments/production/app(4) modules/waf(1) modules/ecs(3) environments/production(2) |
| CKV_AWS_7 | Ensure rotation for customer created CMKs is enabled | 12 | modules/kms(1) environments/production/data(4) environments/production/app(1) environments/shared-services(1) environments/management(1) environments/production(3) environments/security(1) |
| CKV_AWS_18 | Ensure the S3 bucket has access logging enabled | 12 | modules/static-site(1) modules/alb(1) environments/production(1) modules/config(1) environments/security(3) environments/management(1) environments/production/app(2) modules/observability(2) |
| CKV_AWS_356 | Ensure no IAM policies documents allow * as a statement's resource for restrictable actions | 10 | environments/shared-services(2) environments/management(2) environments/security(1) environments/production/app(1) modules/observability(1) modules/kms(1) environments/production/data(2) |
| CKV_AWS_21 | Ensure all data stored in the S3 bucket have versioning enabled | 10 | environments/production/app(1) modules/observability(2) modules/alb(1) environments/production(1) modules/config(1) environments/security(3) environments/management(1) |
| CKV2_AWS_61 | Ensure that an S3 bucket has a lifecycle configuration | 9 | environments/production(1) environments/management(1) modules/config(1) environments/security(3) environments/production/app(2) modules/static-site(1) |
| CKV_AWS_111 | Ensure IAM policies does not allow write access without constraints | 8 | environments/production/app(1) modules/kms(1) environments/production/data(2) environments/shared-services(1) environments/management(2) environments/security(1) |
| CKV_AWS_109 | Ensure IAM policies does not allow permissions management / resource exposure without constraints | 8 | environments/shared-services(1) environments/management(2) environments/security(1) environments/production/app(1) modules/kms(1) environments/production/data(2) |
| CKV_AWS_300 | Ensure S3 lifecycle configuration sets period for aborting failed uploads | 7 | modules/observability(2) modules/cloudtrail(2) environments/security(2) environments/production/app(1) |
| CKV_AWS_145 | Ensure that S3 buckets are encrypted with KMS by default | 6 | modules/cloudtrail(1) modules/alb(1) environments/management(1) environments/security(2) environments/production/app(1) |
| CKV_AWS_226 | Ensure DB instance gets all minor upgrades automatically | 4 | environments/production/data(1) modules/rds(1) modules/aurora(2) |
| CKV2_AWS_3 | Ensure GuardDuty is enabled to specific org/region | 4 | modules/security(1) environments/production(1) environments/security(1) environments/management(1) |
| CKV_AWS_35 | Ensure CloudTrail logs are encrypted at rest using KMS CMKs | 3 | environments/security(1) environments/management(1) modules/cloudtrail(1) |
| CKV_AWS_252 | Ensure CloudTrail defines an SNS Topic | 3 | environments/security(1) modules/cloudtrail(1) environments/management(1) |
| CKV2_AWS_6 | Ensure that S3 bucket has a Public Access block | 3 | environments/security(2) environments/production/app(1) |
| CKV_AWS_86 | Ensure CloudFront distribution has Access Logging enabled | 2 | environments/production/app(1) modules/static-site(1) |
| CKV_AWS_68 | CloudFront Distribution should have WAF enabled | 2 | environments/production/app(1) modules/static-site(1) |
| CKV_AWS_374 | Ensure AWS CloudFront web distribution has geo restriction enabled | 2 | modules/static-site(1) environments/production/app(1) |
| CKV_AWS_336 | Ensure ECS containers are limited to read-only access to root filesystems | 2 | environments/production/app(1) modules/ecs(1) |
| CKV_AWS_310 | Ensure CloudFront distributions should have origin failover configured | 2 | modules/static-site(1) environments/production/app(1) |
| CKV_AWS_192 | Ensure WAF prevents message lookup in Log4j2. See CVE-2021-44228 aka log4jshell | 2 | environments/production/app(1) modules/waf(1) |
| CKV_AWS_162 | Ensure RDS cluster has IAM authentication enabled | 2 | modules/aurora(1) environments/production/data(1) |
| CKV2_AWS_76 | Ensure AWS ALB attached WAFv2 WebACL is configured with AMR for Log4j Vulnerability | 2 | environments/production/app(1) modules/alb(1) |
| CKV2_AWS_47 | Ensure AWS CloudFront attached WAFv2 WebACL is configured with AMR for Log4j Vulnerability | 2 | environments/production/app(1) modules/static-site(1) |
| CKV2_AWS_39 | Ensure Domain Name System (DNS) query logging is enabled for Amazon Route 53 hosted zones | 2 | modules/route53(1) environments/shared-services(1) |
| CKV2_AWS_38 | Ensure Domain Name System Security Extensions (DNSSEC) signing is enabled for Amazon Route 53 public hosted zones | 2 | modules/route53(1) environments/shared-services(1) |
| CKV2_AWS_32 | Ensure CloudFront distribution has a response headers policy attached | 2 | environments/production/app(1) modules/static-site(1) |
| CKV2_AWS_27 | Ensure Postgres RDS as aws_rds_cluster has Query Logging enabled | 2 | modules/aurora(1) environments/production/data(1) |
| CKV2_AWS_19 | Ensure that all EIP addresses allocated to a VPC are attached to EC2 instances | 2 | environments/production(1) modules/vpc(1) |
| CKV2_AWS_12 | Ensure the default security group of every VPC restricts all traffic | 2 | environments/production(1) modules/vpc(1) |
| CKV2_AWS_11 | Ensure VPC flow logging is enabled in all VPCs | 2 | environments/production(1) modules/vpc(1) |
| CKV2_AWS_1 | Ensure that all NACL are attached to subnets | 2 | modules/networking(1) environments/production(1) |
| CKV_AWS_65 | Ensure container insights are enabled on ECS cluster | 1 | modules/ecs(1) |
| CKV_AWS_353 | Ensure that RDS instances have performance insights enabled | 1 | modules/rds(1) |
| CKV_AWS_293 | Ensure that AWS database instances have deletion protection enabled | 1 | modules/rds(1) |
| CKV_AWS_274 | Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy | 1 | environments/management(1) |
| CKV_AWS_161 | Ensure RDS database has IAM authentication enabled | 1 | modules/rds(1) |
| CKV_AWS_157 | Ensure that RDS instances have Multi-AZ enabled | 1 | modules/rds(1) |
| CKV_AWS_150 | Ensure that Load Balancer has deletion protection enabled | 1 | modules/alb(1) |
| CKV_AWS_118 | Ensure that enhanced monitoring is enabled for Amazon RDS instances | 1 | modules/rds(1) |
| CKV2_AWS_10 | Ensure CloudTrail trails are integrated with CloudWatch Logs | 1 | environments/management(1) |
