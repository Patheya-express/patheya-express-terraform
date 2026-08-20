# EKS platform guide

What `modules/eks-addons` installs, and why each one is there — see that module's own README for
the file-by-file breakdown; this page is the "what does a fresh cluster actually have running on
it" summary.

| Component | Namespace | Why |
| --- | --- | --- |
| VPC CNI, CoreDNS, kube-proxy | `kube-system` | EKS bootstrap defaults, adopted and explicitly version-pinned (`core-addons.tf`) |
| EBS CSI driver | `kube-system` | Storage prerequisite (`storage.md`'s "no application volumes yet" — the driver and default StorageClass exist, nothing uses them yet) |
| Karpenter | `kube-system` | Dynamic node provisioning above the managed node groups' on-demand floor — `karpenter-guide.md` |
| AWS Load Balancer Controller | `kube-system` | Provisions the one NLB in front of NGINX |
| NGINX Ingress Controller | `ingress-nginx` | Single entry point for HTTP(S)/WebSocket — `ingress-guide.md` |
| ExternalDNS | `kube-system` | Automatic Route53 record management — `dns-guide.md` |
| cert-manager | `cert-manager` | DNS-01 certificate issuance beyond the NLB's own ACM certificate |
| Metrics Server | `kube-system` | Backs the backend repo's existing HPAs |
| External Secrets Operator | `external-secrets` | Syncs Secrets Manager entries into Kubernetes Secrets — `docs/secrets-guide.md` (Phase 4) |
| PgBouncer | `data-platform` | Aurora connection pooling — `docs/pgbouncer-guide.md` (Phase 4) |

## Namespaces prepared, not populated

`patheya-backend`, `patheya-frontend` (ResourceQuota + LimitRange + Pod Security `restricted`) —
ready for Phase 4+ application deployment. `monitoring`, `logging`, `tracing` — empty, Phase 5
installs into them; this phase only ensures they exist with the right labels so Phase 5's Helm
charts don't need to also create/label them.

## What every addon needs to keep working

Every IRSA role (`modules/eks-addons`) trusts exactly one `system:serviceaccount:<namespace>:<name>`
subject — renaming a Helm release's service account name without updating the matching IRSA trust
policy's `sub` condition breaks that addon's AWS API access silently (the pod runs, AWS calls
return `AccessDenied`). See `irsa-guide.md` for the full mapping.
