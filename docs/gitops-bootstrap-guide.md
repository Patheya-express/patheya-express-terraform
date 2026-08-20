# GitOps bootstrap guide

How the `bootstrap → platform → infrastructure → applications` chain actually comes up, and the
two implementation decisions worth understanding before touching any of it.

## Why `infrastructure` and `applications` are siblings, not a nested chain

The natural-sounding design — `platform`'s Application points at `infrastructure/`, and
`infrastructure/`'s own Kustomize output includes one more `Application` that in turn points at
`applications/` — doesn't actually work. Kustomize's `namespace:` transformer (used in
`infrastructure/overlays/<env>/kustomization.yaml` to stamp `patheya-backend` onto the
PriorityClass/NetworkPolicy) would apply to **every** resource in that kustomization, including
an `Application` object nested inside it — silently rewriting its `metadata.namespace` from
`argocd` to `patheya-backend`, which breaks it (ArgoCD `Application` objects must live in the
`argocd` namespace to be reconciled).

The fix: `platform/<environment>/` creates **two sibling** Applications directly —
`infrastructure-application.yaml` and `backend-application.yaml` — ordered via
`argocd.argoproj.io/sync-wave` annotations (`"0"` and `"1"`) so infrastructure still applies
first, without nesting one Application inside a Kustomize-processed directory.

## Why the backend Application points at `patheya-express-platform` directly

`patheya-express-gitops`'s `platform/<env>/backend-application.yaml` sets `source.repoURL` to
the **application repository**, not to a copy of its manifests vendored into the gitops repo.
This is an interim, deliberate choice:

- No CI/image-promotion pipeline exists yet (Phase 7's GitHub Actions build/scan/sign work,
  explicitly out of this task's scope) — the usual reason a gitops repo holds its own rendered
  copy of manifests is so a CI bot can bump `images.newTag` there without touching the
  application repo. Without that automation, a vendored copy would just be a second place to
  manually keep in sync with `k8s/overlays/<env>` — strictly worse than one source of truth.
- Once Phase 7 exists, migrate by: (1) copying `k8s/base` + overlays into
  `patheya-express-gitops/applications/backend/`, (2) pointing `backend-application.yaml` at the
  new local path instead of the external repo URL, (3) having CI's bot commit target that path
  instead of the application repo. `docs/argocd-guide.md`'s ownership-boundary table doesn't
  change — this only changes where the *source* of the applications-layer manifests lives.

## A required backend-repo fix this work depended on

`patheya-express-platform`'s `k8s/base/kustomization.yaml` (and all three overlays) still
targeted the pre-Phase-3 per-environment-suffixed namespace names
(`patheya-express`/`-dev`/`-staging`) — a gap Phase 3's own final report flagged and explicitly
deferred: *"recommend updating k8s/overlays/*/kustomization.yaml's namespace field in Phase 4
when applications are actually deployed — not touched now per the explicit scope boundary."*
Building `backend-application.yaml` (pointing at those exact overlays, into the
Terraform-created `patheya-backend` namespace) is the moment that gap became load-bearing:

- `k8s/base/namespace.yaml` — **removed**. Terraform (`modules/eks-addons/namespaces.tf`, Phase
  3) is the sole owner of the `Namespace` object; a Kustomize-defined one for the same namespace
  would be a second, conflicting owner.
- `k8s/base/kustomization.yaml` and all three overlays — `namespace:` changed to the unsuffixed
  `patheya-backend`, matching the namespace Terraform already created, in every environment.

Verified: `kubectl kustomize k8s/overlays/{development,staging,production}` all render cleanly,
every namespaced resource stamped `patheya-backend`, no orphaned `Namespace` resource in any of
the three.

## Sequence to actually bring this up (once real AWS credentials exist)

For each environment, in the same order Phase 3/4/5's own bootstrap guide already establishes
(`cluster/` and `data/` in either order, then `platform/`):

1. `terraform apply` in `environments/<env>/platform` — installs ArgoCD, creates the 4
   `AppProject`s and the root `Application`.
2. ArgoCD's root `Application` (automated sync) picks up `bootstrap/<env>/`, which creates
   `platform-<env>` — which in turn creates `infrastructure-<env>` (auto-syncs immediately —
   PriorityClass/NetworkPolicy have no dependency on an application image) and `backend-<env>`
   (stays `OutOfSync`, by design, until a human runs step 3).
3. Once a real, signed image exists in ECR (a future phase) and `k8s/overlays/<env>`'s
   `images.newTag` is updated to reference it: `argocd app sync backend-<env>`.

## Populating repo credentials once real GitHub remotes exist

```bash
aws secretsmanager put-secret-value \
  --secret-id patheya-express/<environment>/argocd-repo-credentials \
  --secret-string '{"username":"<github-username-or-app-id>","password":"<PAT-or-installation-token>"}' \
  --region ap-south-1
```

No Terraform or ArgoCD configuration change is needed to activate this — External Secrets
Operator's `refreshInterval: 1h` (`modules/argocd/secrets.tf`) picks up the new value
automatically. If both repositories end up public, this step can be skipped entirely — an empty
repo-credentials secret is harmless against a public repo, ArgoCD simply doesn't need it.
