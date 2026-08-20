# EKS disaster recovery

Scope: losing an entire EKS cluster (control plane corruption, accidental deletion, unrecoverable
misconfiguration) — not a single node or pod failing, which Kubernetes/Karpenter/the managed node
groups already self-heal without any of this.

## What's actually at risk

The cluster itself holds no durable state — no application data lives in etcd beyond Kubernetes
object definitions, and `storage.md`'s "no application volumes yet" means there are no PVs to lose
either. Everything the cluster runs is reconstructible from this Terraform repo plus the backend
repo's `k8s/` manifests. This makes cluster DR fundamentally a **rebuild-from-code** problem, not a
backup-and-restore problem.

## Recovery procedure

1. `environments/<env>/cluster`: if the VPC/networking/KMS state (Phase 2's flat state) survived,
   `terraform apply` rebuilds the control plane, OIDC provider, node groups, and access entries from
   scratch — typically 15–20 minutes, dominated by EKS control plane creation time.
2. `environments/<env>/platform`: `terraform apply` reinstalls every addon (`eks-addons-guide.md`'s
   table) against the new cluster. Because Karpenter's `EC2NodeClass`/`NodePool` are plain
   `kubernetes_manifest` resources in this same state, they come back automatically — no manual
   Karpenter re-bootstrap step.
3. Backend repo's `k8s/` manifests: reapply via whatever GitOps/CI mechanism is standard at the time
   (this phase only prepares namespaces/RBAC for GitOps — see `eks-platform-guide.md` — it doesn't
   install ArgoCD, so today this step is a manual `kubectl apply -k k8s/overlays/<env>`).
4. DNS: ExternalDNS reconciles Route53 records against the new Ingress/Service objects within one
   sync interval of step 3 completing — no manual Route53 edit needed, but expect a brief propagation
   gap between the new NLB existing and DNS pointing at it.

## What must be preserved outside the cluster for this to work

- Phase 2's flat state (VPC, subnets, security groups, KMS keys, Route53 zone, ACM certificate) —
  if *this* is also lost, recovery time extends to include Phase 2's own rebuild, and the ACM
  certificate must be re-validated (DNS-01, automatic if the zone is intact).
- The S3 state bucket + DynamoDB lock table (`bootstrap/`) — without these, `cluster/` and
  `platform/`'s own Terraform state is gone too, turning a `terraform apply` into a
  `terraform import` exercise. This is why `bootstrap/` uses local state deliberately kept outside
  the blast radius of anything this repo's other states could delete.
- The backend repo's Git history — the actual source of truth for every `k8s/` manifest.

## What this phase deliberately does not provide

Cross-region cluster failover, automated backup of Kubernetes objects (e.g. Velero), and a tested
runbook with measured RTO/RPO numbers — these require the observability and GitOps foundations
this phase only prepares namespaces for (`eks-platform-guide.md`), not installs. Revisit once
Phase 4/5 land; `cloud-architecture-blueprint.md` Section 14 has the target DR posture this phase is
building toward.
