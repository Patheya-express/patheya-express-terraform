# modules/argocd

ArgoCD, installed once by Terraform (like every other addon in this repository), plus the one
seed object — a root `Application` — that hands ongoing platform evolution to Git from that
point forward.

## Ownership boundary (the anti-circularity decision)

| Owned by Terraform | Owned by ArgoCD (via the gitops repo) |
| --- | --- |
| ArgoCD's own Helm release (install + version upgrades — bump the pin in `main.tf`, re-apply, same as Karpenter/NGINX/cert-manager/kube-prometheus-stack/Loki/Tempo) | Everything under `bootstrap/` → `platform/` → `infrastructure/` → `applications/` in the gitops repo |
| The 4 `AppProject`s (`projects.tf`) and the root `Application` (`root-application.tf`) — the seed | PriorityClass/NetworkPolicy for the app namespaces, (eventually) Kyverno, application Deployments |
| Namespace/ResourceQuota/LimitRange for every namespace this tree touches (`argocd` here, `patheya-backend`/`patheya-frontend` from Phase 3) | Nothing namespace-lifecycle-related — every layer's `AppProject.syncOptions` sets `CreateNamespace=false` |
| Karpenter, NGINX, cert-manager, ExternalDNS, AWS Load Balancer Controller, External Secrets Operator, the Prometheus stack, Loki, Tempo, the OTel Collector, Aurora, ElastiCache, PgBouncer | (not migrated to GitOps in this phase — a future phase's explicit decision, not this one's) |

**Why ArgoCD doesn't manage its own Helm release via a self-referential Application**: doing so
would mean the exact same in-cluster object (the `argocd` Helm release) has two possible
reconcilers — Terraform's `helm_release` resource and an ArgoCD `Application` targeting that same
chart. Whichever applied more recently would "win" until the other's next reconciliation, which
is a real, avoidable source of drift/conflict, not a hypothetical one. "The platform can
eventually manage itself" is satisfied by this module's *structure* being ready for that
migration in a future phase (once the gitops repo's promotion/CI story is mature enough to trust
for it), not by building a self-managing loop today that has nowhere safe to land.

## The 4 layers, and why each one doesn't create a cycle

```
bootstrap (Terraform-seeded) -> platform -> infrastructure -> applications
```

Every arrow is one direction only: a parent Application's sync creates its child Applications;
no child ever references anything above it. Each layer's `AppProject` restricts which
repositories it can source from and which namespaces it can touch — `applications`, the
lowest/least-trusted layer, can only ever reach `patheya-backend`/`patheya-frontend`, never
`argocd`/`kube-system`/`monitoring`, even if a manifest in that layer were wrong.

- **bootstrap**: the root `Application` only. Automated sync, self-heals, prunes.
- **platform**: currently a placeholder (nothing Terraform doesn't already own needs GitOps
  management yet) — reserved for Kyverno once Phase 6 builds it.
- **infrastructure**: PriorityClass + NetworkPolicy, sourced from the gitops repo's own copies
  (adapted from the backend repo's `k8s/base/priorityclass.yaml`/`networkpolicy.yaml`) — real,
  automated sync, safe to apply today since neither depends on an application image existing.
- **applications**: api-gateway/workers/frontend — sourced **directly** from each application
  repository's own `k8s/overlays/<env>` (not duplicated into the gitops repo yet — see
  `docs/gitops-bootstrap-guide.md` for why, and the migration path once Phase 7's CI/image-
  promotion pipeline exists to make a separate rendered-manifests repo meaningful). **Manual sync
  only** — this phase's explicit scope is the GitOps engine and its layering, not deploying a
  running application.

## What required a backend-repo fix first

`patheya-express-platform`'s `k8s/base/kustomization.yaml` and all three overlays still targeted
the pre-Phase-3 per-environment-suffixed namespace names (`patheya-express`/`-dev`/`-staging`) —
a gap Phase 3's own final report flagged and explicitly deferred ("not touched now per the
explicit scope boundary"). Building the `applications` AppProject/Application definitions is
exactly the moment that gap became load-bearing, so it's fixed as part of this work — see that
repository's `k8s/base/kustomization.yaml` for the corrected `namespace: patheya-backend` and the
now-removed `namespace.yaml` (Terraform is the sole owner of that object as of Phase 3).

## Access, RBAC, and TLS — current state and what production requires first

**Phase 0 remediation note**: the audit that prompted this section found `server.insecure = "true"`
and `admin_rbac_group` unset in every environment, including production, and asked whether that's
intentional. It is — for the reason below — but it was undocumented as a *boundary*, which is the
actual gap this section closes. No `.tf` change accompanies this: fabricating a real
`admin_rbac_group` value against an IAM Identity Center instance that may not even be enabled yet
(`modules/organizations`' `enable_identity_center`, default `false`) would be a speculative,
unverifiable change, not a fix — this module's existing `admin_rbac_group != null` gate already
does the right thing once a real group exists (see `main.tf`'s `rbac_policy_lines` local).

- **Access today**: `kubectl port-forward` only. No `Ingress` for ArgoCD exists anywhere in this
  repository or (per `docs/argocd-guide.md`) the gitops repo's `infrastructure`/`applications`
  layers — ArgoCD is simply not reachable except by someone with cluster `kubectl` access already
  (itself gated by EKS Access Entries, `modules/eks/access-entries.tf`).
- **Why `server.insecure = "true"` is acceptable *only* under that condition**: it means ArgoCD
  serves plain HTTP inside the cluster. That's a real gap the moment ArgoCD becomes reachable any
  other way (a NodePort, an Ingress, a `LoadBalancer` Service) — plain HTTP would then be exposed
  beyond the cluster boundary, not just within it.
- **Why RBAC is local-admin-only today**: `admin_rbac_group`'s null-safe gate means no group-based
  `role:admin` mapping is fabricated against an Identity Center instance that may not exist. The
  chart's built-in local `admin` account (`configs.cm."admin.enabled" = "true"`) is the only way
  in — acceptable for a single-operator bootstrap phase reachable only via port-forward, not for a
  team, and not once ArgoCD is reachable by anyone who isn't also a cluster operator.

**Required before adding any Ingress for ArgoCD, in order** (this module already supports steps 2
and 4 without a code change — they're variable values, not new resources):

1. Confirm IAM Identity Center is actually enabled for this organization
   (`modules/organizations`' `enable_identity_center = true`, applied from `environments/management`).
2. Set `admin_rbac_group` to a real Identity Center group name for the platform-engineering team —
   this alone adds group-based `role:admin` alongside (not instead of) the local admin account.
3. Flip `configs.params."server.insecure"` to `"false"` and terminate TLS at whatever fronts
   ArgoCD (this module's own `helm_release`, matching how the NGINX Ingress Controller and every
   other addon in this repository terminates TLS — see `docs/ingress-guide.md`).
4. Only then add the Ingress resource itself (in the gitops repo's `infrastructure` layer, per
   this module's own ownership boundary — see the table above), and only then plan to eventually
   set `configs.cm."admin.enabled" = "false"` once SSO login is confirmed working end-to-end (the
   same order Grafana's identical deferred-SSO posture follows, `modules/observability`).

Skipping straight to step 4 — adding an Ingress before 1–3 — is the one sequencing this module's
current defaults were chosen specifically to make hard to do by accident (no Ingress exists in
this repository to accidentally apply), not to make impossible if someone adds one deliberately
without reading this.

## Inputs / Outputs

See `variables.tf` / `outputs.tf`.
