# modules/eks-addons

The "platform" stage — every Helm-based controller and first-class EKS addon the cluster needs
before an application can be deployed onto it, plus namespace/quota preparation. Deployed from
each environment's `platform/` directory, always after that environment's `cluster/`
(`modules/eks`) has already applied — see the repository root README for why these two stages
cannot share one `terraform apply`.

## What's here

| File | Installs |
| --- | --- |
| `core-addons.tf` | VPC CNI (native NetworkPolicy + prefix delegation), CoreDNS, kube-proxy — adopted from EKS's bootstrap defaults, explicitly version-pinned |
| `storage.tf` | EBS CSI driver (+ IRSA) and the default `gp3` StorageClass |
| `karpenter.tf` | Karpenter controller (+ IRSA), SQS + EventBridge spot-interruption handling, `EC2NodeClass`, and two `NodePool`s (on-demand, spot) |
| `aws-lb-controller.tf` | AWS Load Balancer Controller (+ IRSA) — provisions the one NLB in front of NGINX |
| `nginx-ingress.tf` | NGINX Ingress Controller — HA, TLS-terminating NLB Service, PDB |
| `external-dns.tf` | ExternalDNS (+ IRSA), scoped to this environment's own Route53 zone only |
| `cert-manager.tf` | cert-manager (+ IRSA) and a Route53 DNS-01 `ClusterIssuer` |
| `metrics-server.tf` | Metrics Server — what the backend's existing HPAs need to actually scale |
| `namespaces.tf` | `patheya-backend`/`patheya-frontend` (+ quota/limits) and `monitoring`/`logging`/`tracing` (empty, Phase 5 prep only) |

## What's deliberately NOT here

No ArgoCD, no Prometheus/Grafana/Loki, no application workloads, no RBAC for a controller that
doesn't exist yet — this task's own scope boundary (Sections 13–14: "prepare... do NOT install").
A namespace with no matching workload or controller is legitimate preparation; a RoleBinding
pointing at a ServiceAccount nothing has created yet is a placeholder, and this repository doesn't
ship those.

## Ingress resource reuse

The backend repository's `k8s/base/ingress.yaml` — `ingressClassName: nginx`, cookie session
affinity, WebSocket-friendly proxy timeouts — is not duplicated or referenced here. It's an
application-repo manifest (Phase 7 GitOps), already correct against the controller this module
installs, with zero changes required. See the Phase 3 report / `docs/cluster-architecture.md`.

## Usage

See `environments/development/platform/main.tf` for the actual call — every addon in this module
is deployed together, from one `platform/` state, per environment.
