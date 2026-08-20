# IRSA guide

Every controller that calls an AWS API gets its own IAM role, trust-scoped to exactly one
`system:serviceaccount:<namespace>:<name>` — never a shared "addons role."

| Controller | Namespace | Service Account | IAM role (module) | AWS APIs |
| --- | --- | --- | --- | --- |
| Karpenter | `kube-system` | `karpenter` | `karpenter.tf` | EC2 fleet/instance management, IAM instance profile, SQS |
| AWS Load Balancer Controller | `kube-system` | `aws-load-balancer-controller` | `aws-lb-controller.tf` | ELBv2, EC2 (SG/subnet describe), ACM/WAF/Shield associate |
| ExternalDNS | `kube-system` | `external-dns` | `external-dns.tf` | Route53 (one zone) |
| cert-manager | `cert-manager` | `cert-manager` | `cert-manager.tf` | Route53 (one zone, DNS-01 only) |
| EBS CSI driver | `kube-system` | `ebs-csi-controller-sa` | `storage.tf` | EBS volume lifecycle |

No IRSA role for: NGINX Ingress Controller (no AWS API calls — the NLB is provisioned by watching
its `Service`, not by NGINX itself calling AWS), Metrics Server (reads kubelet only), CoreDNS/
kube-proxy/VPC CNI (managed as first-class EKS addons, not IRSA-based controllers).

## Renaming a Service Account

If a future Helm chart upgrade changes a controller's default Service Account name, the
corresponding `data.aws_iam_policy_document.*_assume`'s `StringEquals` condition on
`${var.oidc_provider_url}:sub` must be updated in the same change — otherwise the pod runs but
every AWS API call it makes returns `AccessDenied`, silently, until someone notices.

## OIDC provider

One per cluster (`modules/eks/main.tf`), thumbprint fetched live via the `tls_certificate` data
source rather than hardcoded — see that module's comment for why (the same reasoning, and the same
fix, as Phase 2's GitHub OIDC provider typo).
