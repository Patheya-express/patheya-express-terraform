# EKS bootstrap guide

Continues directly from `bootstrap-guide.md`'s Phase 2 sequence — this assumes every environment's
flat `environments/<env>/` (VPC, networking, Route53, KMS, IAM) is already applied.

For each of `development`, `staging`, `production`, in order (an environment's `platform/` can
only apply after that same environment's `cluster/` **and** `data/` (Phase 4 — Aurora, ElastiCache,
Secrets Manager; see `docs/data-platform-architecture.md`) have already applied — `cluster/` and
`data/` have no dependency on each other and can apply in either order or in parallel. No other
cross-environment ordering constraint exists, so development/staging/production can be done in any
order relative to each other):

## 1. `cluster/`

```bash
cd environments/development/cluster
cp terraform.tfvars.example terraform.tfvars   # set your real office/VPN CIDR
# Edit backend.tf with the real account ID
terraform init && terraform plan && terraform apply
```

This is a slow apply (EKS control plane creation alone typically takes 10–15 minutes) — expected,
not a hang.

## 2. `data/` (Phase 4 — can run before, after, or in parallel with step 1)

```bash
cd environments/development/data
terraform init && terraform plan && terraform apply
```

Aurora cluster creation is the slow part here too (10–15 minutes for a provisioned cluster;
faster for development/staging's Serverless v2).

## 3. `platform/`

```bash
cd environments/development/platform
# Edit backend.tf with the real account ID
terraform init && terraform plan && terraform apply
```

Requires the AWS CLI to be installed and configured with credentials for this same account and role
in the *local* environment running `terraform apply` — the `kubernetes`/`helm` providers shell out
to `aws eks get-token` (see `versions.tf`), they don't accept credentials directly.

## 4. Verify

```bash
aws eks update-kubeconfig --name patheya-development --region ap-south-1
kubectl get nodes
kubectl get pods -n kube-system
kubectl get ingressclass
kubectl get pods -n data-platform
kubectl get externalsecrets -A
```

Expect: 3 `system` nodes + the configured `application` floor, every `kube-system` addon pod
`Running`, an `nginx` IngressClass marked default, PgBouncer pods `Running` in `data-platform`,
and every `ExternalSecret` in `SecretSynced` status.

## Production-specific step

`environments/production/platform` needs `apex_zone_id`/`apex_certificate_arn` from
`environments/shared-services`'s outputs (cross-account, supplied as tfvars — see that
environment's `terraform.tfvars.example`), not a remote-state read. Apply `environments/shared-services`
(Phase 2) first if you haven't already.

## What's not covered here

IAM Identity Center-based human `kubectl` access (EKS Access Entries for the four permission sets
from Phase 2) — added once `enable_identity_center` is turned on; see `modules/eks/main.tf`'s
`access_entries` comment in each `cluster/main.tf`. Until then, cluster access for a human is via
the same `OrganizationAccountAccessRole` break-glass path Phase 2's bootstrap guide already uses.
