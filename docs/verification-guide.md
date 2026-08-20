# Verification guide

How `modules/supply-chain-security`'s `verify-image-signatures` `ClusterPolicy` actually decides
whether a pod create is allowed into `patheya-backend`/`patheya-frontend`.

## The check, step by step

1. A pod create request for `patheya-backend`/`patheya-frontend` reaches the API server.
2. Kyverno's admission controller webhook intercepts it (before the request server-side-applies).
3. For each container image matching `${ecr_registry_host}/patheya-express/*`, Kyverno's
   `verifyImages` rule fetches the image's signature from ECR (an OCI artifact reference derived
   from the image digest — the same registry call `docs/signing-guide.md`'s `cosign sign` pushed
   to).
4. The signature's embedded Fulcio certificate is checked against `issuer` and
   `subjectRegExp` (`docs/signing-guide.md`'s table).
5. The signature's Rekor transparency-log inclusion proof is checked against
   `https://rekor.sigstore.dev` — confirming the signature was actually logged publicly at
   signing time, not fabricated after the fact.
6. If all of the above pass: admitted. If any fail (no signature, wrong issuer, wrong subject, no
   valid Rekor entry): **rejected**, with a Kyverno-generated error message naming which check
   failed, returned directly to whatever created the pod (`kubectl`, or — the intended path —
   ArgoCD's own sync, which surfaces the rejection as a sync error).

## What this means today

No image has ever been signed (no CI exists). Every pod create in `patheya-backend`/
`patheya-frontend` is rejected, unconditionally, until that changes. This is the deliberate gate
this phase's OBJECTIVE describes — verify this yourself:

```bash
kubectl run test-pod --image=<ecr-registry>/patheya-express/api-gateway:latest -n patheya-backend
# Expect: admission webhook "validate.kyverno.svc-fail" denied the request:
# resource Pod/patheya-backend/test-pod was blocked due to the following policies:
# verify-image-signatures: ...
```

(This also, incidentally, re-confirms `disallow-latest-tag` and `require-approved-registries`
from `policies-baseline.tf` — several policies would independently reject this same test pod for
several independent reasons, which is the point of defense-in-depth admission policy, not
redundancy for its own sake.)

## Manually verifying a signature outside the cluster

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/patheya-express/patheya-express-platform/\.github/workflows/.+@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <ecr-registry>/patheya-express/api-gateway@sha256:<digest>
```

Same trust anchor Kyverno's policy checks, run by hand — useful for confirming a signature is
valid before even attempting a deploy, or for auditing an image's provenance after the fact.

## Failure mode: what happens if Kyverno itself is down

`kyverno.tf`'s `config.resourceFiltersExcludeNamespaces` only excludes `kube-system`/
`kube-node-lease`/`kube-public` — it does **not** set a cluster-wide `failurePolicy: Ignore`.
Kyverno's chart default (`failurePolicy: Fail` on the admission webhook) means: if every Kyverno
admission-controller replica is unreachable, pod creates in `patheya-backend`/`patheya-frontend`
**fail closed** (rejected, not silently admitted) — matching this phase's OBJECTIVE ("nothing
...should be able to bypass image verification") literally, including during a Kyverno outage.
The tradeoff is availability: a Kyverno outage in production blocks new deploys entirely until
it's resolved. This is why production runs 3 admission-controller replicas with a PDB
(`kyverno.tf`) — the intended mitigation is "don't let Kyverno go down," not "let deploys through
if it does."
