# Policy guide

Every Kyverno `ClusterPolicy` this phase created, what it checks, and — the one thing worth
understanding before touching any of them — **why every one of them matches only
`patheya-backend`/`patheya-frontend`**.

## The enforcement-scope decision

See `modules/supply-chain-security/README.md`'s own section on this, restated briefly: a
cluster-wide policy in Enforce mode would, on the next reconciliation of any already-running
Terraform-managed addon, start rejecting updates to pods whose upstream Helm chart's default
`securityContext` this phase never audited — and has no authority to change without redesigning
those charts' values. Every policy below matches `patheya-backend`/`patheya-frontend` only.
Visibility into every *other* namespace's configuration posture is Trivy Operator's
`ConfigAuditReport` job (`docs/observability-guide.md`'s Data Platform/Infrastructure dashboards
would be the natural home for surfacing it — not built as a dashboard in this phase, since Trivy
Operator itself is new this phase and hasn't produced a first report yet to build a dashboard
against).

## The 16 baseline policies

| Policy | Mode (default) | Checks |
| --- | --- | --- |
| `disallow-latest-tag` | `kyverno_policy_mode` | Image tag is not `:latest` and not absent |
| `require-resource-requests-limits` | `kyverno_policy_mode` | Every container sets cpu+memory requests and limits |
| `require-probes` | `kyverno_policy_mode` | Every container sets livenessProbe + readinessProbe |
| `require-non-root` | `kyverno_policy_mode` | `runAsNonRoot: true` at pod or container level |
| `require-readonly-root-filesystem` | `kyverno_policy_mode` | Every container sets `readOnlyRootFilesystem: true` |
| `require-pod-security-restricted` | `kyverno_policy_mode` | `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, seccomp `RuntimeDefault`/`Localhost` — a second, independent check of what PSA "restricted" already enforces at the API server |
| `require-approved-registries` | `kyverno_policy_mode` | Every image comes from `${ecr_registry_host}/patheya-express/*` |
| `require-labels` | `kyverno_policy_mode` | Every pod carries the full `app.kubernetes.io/*` label set |
| `require-annotations` | `kyverno_policy_mode` | Every pod carries `patheya-express.io/git-commit` + `.../build-id` |
| `block-privileged-containers` | `kyverno_policy_mode` | `securityContext.privileged` is never `true` |
| `block-host-namespaces` | `kyverno_policy_mode` | `hostNetwork`/`hostPID`/`hostIPC` are never `true` |
| `block-unsafe-capabilities` | `kyverno_policy_mode` | No container adds any Linux capability |
| `block-hostpath-volumes` | `kyverno_policy_mode` | No `hostPath` volume anywhere in the pod spec |
| `verify-image-signatures` | `image_verification_policy_mode` (**Enforce**, independent of the above) | Cosign keyless signature, valid Fulcio identity, valid Rekor entry — `docs/verification-guide.md` |
| `verify-sbom-attestation` | Always `Audit` | CycloneDX SBOM attestation present — `docs/sbom-guide.md` |

That's 15 rows; `block-host-namespaces` covers 3 of this task's Section 2 named items
(hostNetwork, hostPID, hostIPC) in one policy, bringing the total named checks to the full 17.

## Per-environment mode

| Environment | Baseline policies | Image verification |
| --- | --- | --- |
| Development | Audit | Enforce |
| Staging | Enforce | Enforce |
| Production | Enforce | Enforce |

Development runs baseline policies in Audit — fast iteration while nothing is deployed yet,
matching `k8s/overlays/development`'s own already-more-relaxed posture (local storage driver,
`LOG_TO_FILE=true`). Image signature verification is Enforce **everywhere**, unconditionally —
this phase's core guarantee doesn't get a softer development mode, because the whole point is
that no environment should ever run an unverified image, not just production.

## Reading a policy violation

```bash
kubectl get clusterpolicyreport -A
kubectl describe policyreport -n patheya-backend
```

Each failed rule reports the exact resource, the exact rule name, and the policy's own `message`
field (every policy in this phase writes a message naming the actual requirement and, where
relevant, the doc that explains why).

## Adding a new policy

Add a new `kubernetes_manifest` resource to `policies-baseline.tf` (or a new file, if it's a
different category of concern) — same `local.app_namespaces` match scope, same
`var.kyverno_policy_mode` reference, same annotation shape (`policies.kyverno.io/title`/
`severity`/`category`) as every existing one, so `kubectl get clusterpolicy -o wide` stays
self-documenting.
