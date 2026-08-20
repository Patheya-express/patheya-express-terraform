# modules/supply-chain-security

Kyverno (admission control), Trivy Operator (in-cluster vulnerability/config/RBAC/compliance
scanning), Falco + falcosidekick (runtime detection) — called from `platform/main.tf` alongside
`eks_addons`, `observability`, and `argocd`.

## The enforcement-scope decision (read this before touching `policies-baseline.tf`)

Every baseline Kyverno policy matches **only** `patheya-backend`/`patheya-frontend`. A
cluster-wide "require non-root" or "require resource limits" policy would, on the very next
reconciliation of any already-running Terraform-managed addon (Karpenter, the AWS Load Balancer
Controller, NGINX, cert-manager, ExternalDNS, External Secrets Operator, the Prometheus stack,
Loki, Tempo, the OTel Collector, ArgoCD), start rejecting updates to pods whose upstream Helm
chart's default `securityContext` this phase never audited line-by-line — and has no authority to
change without redesigning those charts' values ("Do NOT redesign anything"). Every namespace
this repository has built in Phases 3–6 stays completely outside these policies' match scope; if
visibility into whether they comply matters, that's what Trivy Operator's cluster-wide
`ConfigAuditReport`s are for (report-only, never admission-blocking).

`verify-image-signatures` (the one Section 2/Section 6 item this phase's OBJECTIVE calls out
explicitly — "nothing deployed after this phase should be able to bypass image verification") is
controlled by its own variable, `image_verification_policy_mode`, separately from every other
policy's shared `kyverno_policy_mode` — because it's the actual security guarantee this whole
phase exists to deliver, not one best-practice check among many.

## What this means in practice, today

No CI pipeline exists yet (a future phase's explicit scope — this one deliberately excludes
GitHub Actions). `verify-image-signatures` defaults to `Enforce`. The practical consequence: **no
pod can be created in `patheya-backend`/`patheya-frontend` at all**, by design, until a future
phase's CI pipeline produces a cosign-signed image in ECR. This is the deliberate gate the
OBJECTIVE describes, not a bug to work around.

## Kyverno's four controllers

Admission (validates/mutates on the request path — HA'd to 3 replicas + a PDB in production,
since this one is on the live pod-creation path for the *entire* cluster, not just the two app
namespaces its policies match), background (re-evaluates existing resources against policies
added after they were created), cleanup (TTL-based resource cleanup — installed, unused by any
policy in this phase), reports (aggregates `PolicyReport`/`ClusterPolicyReport` objects).

## IRSA

Kyverno's admission and background controllers, plus Trivy Operator, each get their own IRSA role
scoped to `ecr:GetAuthorizationToken` (account-wide, no per-registry ARN exists for this specific
action) plus `BatchGetImage`/`GetDownloadUrlForLayer`/`DescribeImages`/`DescribeRepositories`
scoped to `patheya-express/*` repositories — needed because signature/attestation/vulnerability
data is fetched by the pod itself via a direct registry API call, not via kubelet's own image
pull (which already works through the node role, unrelated to this).

## Falco is the one namespace in this whole repository labeled Pod Security "privileged"

Deliberately, not by oversight — see `namespaces.tf`'s comment. Runtime syscall detection via
eBPF fundamentally needs host-level access that Pod Security "restricted" exists specifically to
prevent; labeling the namespace "restricted" wouldn't shrink Falco's actual privilege, it would
just make the label false the moment Falco's own pod tried to start.

## GitOps integration

Kyverno/Trivy/Falco are Terraform-owned, not ArgoCD-owned — consistent with every IRSA-needing
addon already in this repository (Loki, Tempo, Grafana, ExternalDNS, cert-manager, the ALB
Controller) and with this phase's own "Terraform only" requirement. `patheya-express-gitops`'s
`platform/<env>/README.md` previously reserved that layer for Kyverno as a forward-looking
placeholder written during the ArgoCD phase — that placeholder is now superseded and has been
updated to reflect this decision. `modules/argocd` gained one small addition this phase: resource
health-check customizations so ArgoCD's own UI correctly reports Kyverno `ClusterPolicy`/
`PolicyReport` and Falco/Trivy CRDs as healthy rather than "Unknown" (ArgoCD has no built-in
health check for CRDs it didn't ship).

## Inputs / Outputs

See `variables.tf` / `outputs.tf`.
