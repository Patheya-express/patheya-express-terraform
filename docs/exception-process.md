# Exception process

How a workload gets a documented, reviewed exemption from a policy in `docs/policy-guide.md` —
not by editing the policy, and not by a raw `kubectl apply` against a running cluster
(platform-standards.md Section 1, principle 5: GitOps, no direct cluster mutation).

## The mechanism: Kyverno `PolicyException`

`modules/supply-chain-security/kyverno.tf` enables Kyverno's `PolicyException` feature
(`enablePolicyException: true`, `exceptionNamespace: kyverno`) — a namespaced CRD that names a
specific policy, a specific rule within it, and a specific resource match, and exempts exactly
that combination. A `PolicyException` never disables a policy platform-wide; it always narrows to
the smallest match that solves the actual problem.

```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: api-gateway-readonly-fs-exception
  namespace: kyverno
spec:
  exceptions:
    - policyName: require-readonly-root-filesystem
      ruleNames:
        - readonly-root-fs
  match:
    any:
      - resources:
          kinds: [Pod]
          namespaces: [patheya-backend]
          selector:
            matchLabels:
              app.kubernetes.io/name: some-legacy-component
  conditions:
    all:
      - key: "{{ request.object.metadata.labels.\"app.kubernetes.io/name\" }}"
        operator: Equals
        value: some-legacy-component
```

## Where it lives

`patheya-express-gitops`'s `platform/<environment>/` layer — reviewed via the same PR process as
every other change to that repository, not applied directly to a running cluster. This is
deliberate: an exception is a policy decision, and policy decisions get the same review bar as
the policy itself (`platform-standards.md` Section 23's ADR-review-bar reasoning applied to a
smaller, per-resource decision).

## The review bar

1. **State the specific requirement that can't be met**, and why — "the resource doesn't support
   X" is not sufficient; "the resource doesn't support X because Y, confirmed by Z" is.
2. **Scope the match as narrowly as possible** — a label selector matching one specific
   component, never a bare namespace match that would exempt everything in
   `patheya-backend`/`patheya-frontend` from that policy.
3. **State an expiry or a review trigger** — an exception with no removal condition is exactly
   the "deliberate, time-boxed shortcut that quietly becomes permanent"
   `platform-standards.md` Section 1 (principle 2) already forbids for code; the same standard
   applies to a policy exception. Record the expiry in the `PolicyException`'s own
   `metadata.annotations` (Kyverno doesn't natively expire these — the cleanup controller
   installed by this phase, currently unused by any policy, is the natural mechanism to wire up
   TTL-based expiry once a real exception exists to test it against).
4. **Two-approver review** (`platform-standards.md` Section 3's bar for anything touching
   `modules/` — the same bar applies here, since an exception is functionally a targeted policy
   change) — at least one reviewer with platform-security context, not just anyone with merge
   rights to the gitops repo.

## What does NOT go through this process

Changing `image_verification_policy_mode`/`kyverno_policy_mode` from `Enforce` to `Audit`
platform-wide is not an exception — it's a policy change, made in `patheya-express-terraform`,
through that repository's own two-approver bar for anything touching `modules/`. The exception
mechanism exists specifically so a real, narrow, individual-resource problem never becomes an
argument for weakening the platform-wide default to solve it.

## Current state

No exception has ever been granted — nothing is deployed yet (this phase's explicit scope).
`patheya-express-gitops/platform/<environment>/` holds no `PolicyException` manifests today.
