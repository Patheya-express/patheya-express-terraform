# EKS upgrade guide

EKS supports one minor version skip per upgrade (e.g. 1.29 → 1.30, never 1.29 → 1.31 directly) —
every upgrade in this repo follows the same control-plane-then-nodes-then-addons order below,
once per minor version, even when jumping several versions.

## Order

1. **Control plane**: bump `cluster_version` in `environments/<env>/cluster/terraform.tfvars`,
   `terraform apply`. EKS upgrades the control plane in place; existing nodes keep running on the
   old kubelet version during this step (the control plane tolerates a one-minor-version skew).
2. **Managed node groups**: bump the same version isn't a separate variable — `modules/eks`'s node
   groups inherit the cluster's Kubernetes version automatically, so triggering a node group update
   (`terraform apply` again, or `aws eks update-nodegroup-version` for a manual rolling replacement)
   is the actual upgrade action. Respect the existing PDBs (`ingress-guide.md`) — a node group update
   drains one node at a time and will stall, not fail, if a PDB can't be satisfied.
3. **Karpenter-provisioned nodes**: no explicit action — Karpenter's `EC2NodeClass` always resolves
   the latest AL2023 AMI for the cluster's current Kubernetes version at the moment it provisions a
   node, and `consolidateAfter` naturally cycles old nodes out. To force it immediately rather than
   waiting for natural consolidation, drift the NodePool (e.g. touch a label) or manually cordon/drain.
4. **Core addons** (VPC CNI, CoreDNS, kube-proxy, EBS CSI): version-pinned in
   `modules/eks-addons/core-addons.tf` — bump the pins to the versions EKS's addon compatibility
   matrix lists for the new cluster version, `terraform apply`.
5. **Helm-installed addons** (Karpenter, AWS Load Balancer Controller, NGINX, ExternalDNS,
   cert-manager, Metrics Server): each chart version is pinned in its own `.tf` file — bump and
   apply independently of the cluster version bump; these follow their own upstream release
   cadence, not EKS's.

## Why control plane first

An EKS control plane can run one minor version ahead of its nodes but never behind them — upgrading
nodes before the control plane is rejected outright. Same applies to Karpenter-provisioned nodes:
they inherit the target version from the (already-upgraded) control plane's Kubernetes version
metadata, not the other way around.

## Environment sequencing

Development → staging → production, never in parallel and never skipping a lower environment,
matching `platform-standards.md`'s promotion-not-parallel-deploy rule. Let a version soak in
development for at least the length of one on-call rotation before promoting.

## Rollback

EKS control plane upgrades are not reversible in place. If a new version misbehaves, the mitigation
is rolling the *node groups* back to the previous AMI release (still on the new control plane
version, since that step can't undo) or, in the worst case, restoring `cluster/` state to build a
replacement cluster at the prior version — not a `terraform apply` of a lowered `cluster_version`,
which AWS rejects.
