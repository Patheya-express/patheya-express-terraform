# ArgoCD guide

`modules/argocd` — installed once per environment (one ArgoCD per cluster, matching the
one-cluster-per-environment model), called from `platform/main.tf` alongside `eks_addons` and
`observability`.

## The ownership boundary — why this doesn't create a circular dependency

Treating "ArgoCD as the deployment engine" raised one real question: does ArgoCD manage itself?
The answer here is deliberately **no, not yet** — see `modules/argocd/README.md`'s full table,
summarized:

- **Terraform owns**: ArgoCD's own Helm release (installed and upgraded exactly like every other
  addon — Karpenter, NGINX, cert-manager, the Prometheus stack, Loki, Tempo — bump the pin,
  re-apply), the 4 `AppProject`s, and the one root `Application` that seeds everything else.
- **ArgoCD owns** (via the `patheya-express-gitops` repository): the `platform` layer
  (reserved for future Kyverno `PolicyException` grants — see `docs/exception-process.md`; the
  Kyverno/Trivy Operator/Falco engines themselves are Terraform-owned,
  `modules/supply-chain-security`, for the same IRSA-needs-Terraform reason as everything else in
  this list), the `infrastructure` layer (PriorityClass + NetworkPolicy), and the `applications`
  layer (the backend `Application`, manual sync only).

A self-referential Application that manages ArgoCD's own Helm release was deliberately **not**
built. Doing so would give the same in-cluster object (the `argocd` release) two possible
reconcilers — Terraform's `helm_release` and an ArgoCD `Application` targeting the same chart —
which is a real, not hypothetical, source of drift. "Structure it so the platform can eventually
manage itself" is satisfied by every layer below ArgoCD's own install being genuinely
Git-driven today, with the *structure* ready for a future phase to migrate ArgoCD's own
lifecycle into that same tree once the gitops repo's promotion/review process is mature enough
to be trusted for it — not by building that self-reference now with nowhere safe for it to land.

## The 4 layers

```
bootstrap (Terraform-seeded, per environment)
  -> platform (reserved for future Kyverno PolicyException grants + triggers the next two)
    -> infrastructure (PriorityClass + NetworkPolicy — automated sync)
    -> applications (the backend Deployment — manual sync only)
```

`infrastructure` and `applications` are siblings, both created by `platform`, ordered via
`argocd.argoproj.io/sync-wave` annotations (`0` then `1`) rather than one nested inside the
other — see `docs/gitops-bootstrap-guide.md` for why a literal nested chain doesn't work with
Kustomize-rendered directories.

Each layer's `AppProject` (`projects.tf`) enforces the boundary structurally, not just by
convention: `applications`' destinations are `patheya-backend`/`patheya-frontend` only — it
cannot target `argocd`/`kube-system`/`monitoring` even if a manifest in that layer were wrong.

## RBAC

`role:readonly` is the default policy for anyone with cluster access; `role:admin` is granted to
`var.admin_rbac_group` only once it's set (an IAM Identity Center group name) — no fabricated
group mapping against an Identity Center instance that may not be enabled yet (Phase 2's
`enable_identity_center` gate). Until then, the built-in local `admin` account (chart default,
`configs.cm."admin.enabled" = true`) is the only way in — retrieve its auto-generated password
the same way any `argo-cd` chart install documents (`kubectl -n argocd get secret
argocd-initial-admin-secret`).

## Access

No Ingress in this phase — same posture as Grafana (`docs/grafana-guide.md`): reach the UI via

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## Repository credentials

One repo-credential template (`secrets.tf`), matched by URL prefix
(`https://github.com/patheya-express/`), covering both the gitops repo and the backend repo.
Synced via the same `ClusterSecretStore` Phase 4 installed — no second External Secrets Operator.
Empty today (both repositories are local-only); see `docs/gitops-bootstrap-guide.md` for exactly
what to populate once real GitHub remotes exist.

## Sync windows

Production's `applications` `AppProject` carries a `deny` sync window outside typical
platform-engineering hours (`00:00–08:00` and `20:00–00:00` UTC) — belt-and-suspenders on top of
every `Application` in that layer already being manual-sync-only, matching
`cloud-architecture-blueprint.md` Section 9's "requires manual approval ... for production."
