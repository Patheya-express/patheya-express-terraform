# Production lifecycle — idle / build / live

Production (account `512297269884`, `ap-south-1`) keeps its full live architecture in Terraform at
all times. What changes between operating modes is only *how much of it is running*. Pre-launch,
Production spends most of its time in **idle**; **build** brings up enough runtime to develop the
production platform; **live** is the launched system. Nothing in this document weakens the live
architecture — three AZs, three NAT Gateways, private-only EKS, Tailscale admin access and every
security service are the same in every mode that runs them.

## What exists in each mode

| Layer (state key) | Resource | idle | build | live |
|---|---|---|---|---|
| root (`production/terraform.tfstate`) | IAM, GitHub OIDC, permission boundary | ✅ | ✅ | ✅ |
| | KMS: `cloudtrail-logs`, `admin-connectivity`, `eks-secrets` | ✅ | ✅ | ✅ |
| | Config, GuardDuty, Security Hub, Access Analyzer, flow logs | ✅ | ✅ | ✅ |
| | VPC, 9 subnets, IGW, route tables, security groups | ✅ | ✅ | ✅ |
| | EKS control-plane log group (`eks-persistent.tf`, `prevent_destroy`) | ✅ | ✅ | ✅ |
| | NAT Gateways + EIPs + private-app default routes | — | 3 (per AZ) | 3 (per AZ) |
| | Tailscale subnet router (ASG) | 0 | 1 | 1 |
| | GitHub runner (ECS service) | 0 | 1 | 1 |
| cluster (`production/cluster/…`) | EKS 1.36, `STANDARD` support, managed vpc-cni/kube-proxy/coredns | destroyed | ✅ | ✅ |
| | system node group (m6i.large) | — | 2 | 3 |
| | application node group (m6i.xlarge/m6a.xlarge) | — | 1 (min 0, max 2) | 3 (max 10) + Karpenter |
| | Access entries: Terraform CI role, SSO PlatformAdministrator | — | ✅ | ✅ |
| platform (`production/platform/…`) | add-ons, ingress, ArgoCD, observability, supply-chain | destroyed | reduced sizing, no PgBouncer / data ExternalSecrets | full sizing |
| data (`production/data/…`) | Aurora HA, Redis HA, app secrets, DR backup vault | never in idle | **not deployed** | ✅ |

The mode is declared per layer in a committed `operating-mode.auto.tfvars` (root, cluster,
platform). The variable has no default, is validated, and a mode change is therefore a reviewed
Git change. The cluster and platform layers accept only `build` or `live` — in idle they are
destroyed, never applied. The data layer has no mode: it is applied once, at launch, and after
that is never part of a stop.

## Why each runtime resource is destroyed or scaled rather than "stopped"

| Resource | Idle action | Reason |
|---|---|---|
| EKS cluster + node groups | destroy the cluster layer | EKS has no stopped state; the control plane bills hourly while it exists |
| NAT Gateways + EIPs | `enable_nat_gateway = false` | no stopped state; nothing in private-app needs egress with no cluster, router or runner |
| Tailscale router | ASG 0 (launch template, role, SG, auth-key secret kept) | its only purpose is reaching the EKS private endpoint |
| GitHub runner | ECS desired 0 (task definition, role, PAT secret kept) | only needed to reach the EKS private endpoint |
| Platform | destroy the platform layer first | controllers create NLBs, EBS volumes and DNS records that would otherwise be orphaned |

The EKS control-plane log group and the `eks-secrets` KMS key live in the root layer so that
destroying a cluster never deletes its audit history or the key encrypting it.

## Ordering

```
start (idle → build|live)                     stop (build|live → idle)
  1. root      operating_mode=build|live        1. platform  destroy
  2. cluster   apply                            2. cluster   destroy
  3. data      apply            (live only)     3. root      operating_mode=idle
  4. platform  apply (via Tailscale or runner)  (data is NEVER destroyed by stop)
```

`cluster` reads `eks_secrets_kms_key_arn` and `eks_cluster_log_group_name` from root state, so the
root layer must be applied (with this change) before the first cluster plan can succeed.
`platform` in `live` mode reads the data layer's state; in `build` it does not read it at all.

## Lifecycle command safety requirements

The future `scripts/patheya-prod.sh {status | start --mode build|live | stop}` must enforce, before
any plan/apply/destroy:

1. **Account**: `aws sts get-caller-identity` account is exactly `512297269884`.
2. **Region**: `ap-south-1` for every command (`AWS_REGION` and the provider's `aws_region`).
3. **Identity**: the caller ARN is `assumed-role/AWSReservedSSO_PlatformAdministrator_*` (human)
   or `patheya-production-terraform-role` (CI via GitHub OIDC) — never an IAM user or access key.
4. **Git**: clean working tree; the committed `operating-mode.auto.tfvars` of each layer matches
   the requested mode (the script commits nothing itself).
5. **Terraform lock**: no active entry for the layer's state key in
   `patheya-express-terraform-locks`; Terraform's own locking stays on (never `-lock=false`).
6. **Plan allowlist**: every apply uses a saved plan; `terraform show -json` is checked so a root
   plan may only touch NAT/EIP/route/router-ASG/runner-service (and nothing may be destroyed
   outside those), and a cluster/platform destroy may only contain that layer's own addresses.
   Anything else aborts. No `-target`, ever.
7. **Data safety**: `stop` refuses to proceed if `production/data/terraform.tfstate` holds any
   resource. Data-layer destruction is a separate, individually approved operation with a final
   snapshot and deletion protection removed in a reviewed change first.
8. **Orphan check** after platform destroy: no load balancer, target group, EBS volume or ENI
   tagged `kubernetes.io/cluster/patheya-production`, and no ELB in the VPC, before the cluster is
   destroyed.
9. **Confirmation**: destructive operations require typing `patheya-production` — never y/n.
10. **Logging**: every run tees plan text, apply output and caller identity to
    `logs/lifecycle-<UTC timestamp>-<command>.log`.
11. **Failure handling**: stop at the first failed step; every step is idempotent, so recovery is
    re-running the same command. State is versioned in S3 for rollback of a corrupted state.
12. **Health gates** on start: NAT Gateways `available`; router instance `InService` and online in
    the tailnet; cluster `ACTIVE`, node groups `ACTIVE`, nodes `Ready`, managed add-ons `ACTIVE`.

## Versions and known prerequisites before the platform layer runs on 1.36

- Managed add-ons are pinned to EKS's 1.36 defaults (cluster/main.tf); re-check with
  `aws eks describe-addon-versions --kubernetes-version 1.36` before each cluster creation.
- modules/eks-addons pins Karpenter chart `1.0.6`, AWS Load Balancer Controller `1.11.0` and
  ingress-nginx `4.11.3`; each must be checked against its Kubernetes 1.36 compatibility matrix,
  and ingress-nginx's upstream retirement assessed, before the platform layer is applied.
- Build capacity needs 8 vCPU of on-demand standard instances (plus the router's 2): the account's
  current quota is 8, with a 32-vCPU increase request open.
