# Incident response

What to do when each layer of this phase's defense-in-depth actually catches something —
companion to `docs/sre-operations-guide.md` (Phase 5), scoped to supply-chain/runtime-security
specifically.

## The four layers, and what each one catches that the others don't

| Layer | Catches | Doesn't catch |
| --- | --- | --- |
| Kyverno admission | A non-compliant or unsigned pod *before* it ever starts | Anything about a pod's behavior once it's already running and admitted |
| Trivy Operator | A CVE disclosed *after* an already-running image was admitted clean | Anything that isn't a known, published CVE |
| ECR native scanning (Phase 2) | The same, for images sitting in the registry, deployed or not | Runtime behavior — it only ever looks at image contents |
| Falco | What an already-running, already-admitted, already-scanned-clean container actually *does* at the syscall level | Anything that never manifests as an anomalous syscall pattern (e.g., a logic-level application bug) |

An incident's first question is always "which layer caught this," because that answer determines
what's actually known and what still needs investigating.

## `Critical-Falco-RuntimeAlertTriggered` fired

This is the most urgent alert this phase adds — by definition, everything upstream (image
signature, admission policy, vulnerability scan) already passed, and something is happening in a
running container that Falco's default ruleset considers dangerous enough to flag at
Critical/Emergency/Alert priority.

1. **Identify the pod and rule**: the alert's `rule` label names the specific Falco rule that
   fired (e.g., "Terminal shell in container," "Write below binary dir," "Outbound connection to
   C2 server") — check Falco's own event detail (`kubectl logs -n falco -l app.kubernetes.io/name=falco`
   or the Loki dashboard, namespace `falco`) for the specific process/file/connection involved.
2. **Do not `docker exec`/`kubectl exec` to "quickly check"** — `platform-standards.md` Section 1
   (principle 6): "`docker exec` into a production container to 'quickly fix something' is an
   incident, not a maintenance action." The same applies to investigating one — exec access
   itself changes the container's state and can destroy the evidence a real investigation needs.
3. **Isolate, don't kill, if the rule suggests active compromise** (not a false positive): a
   `NetworkPolicy` denying all egress/ingress for that specific pod (label-selector-scoped,
   applied via the same GitOps path as everything else) stops it from doing further damage while
   preserving it for forensic inspection — deleting the pod immediately destroys the evidence a
   root-cause investigation needs.
4. **Check the image's own signature/scan history**: was this image ever verified
   (`docs/verification-guide.md`)? Was it clean on Trivy Operator's last scan? If both are yes,
   this is very likely either a runtime-only compromise (a dependency pulled at container start,
   not baked into the image) or a Falco false positive against legitimate but unusual behavior —
   both are real findings, investigated differently.

## `Critical-Trivy-CriticalVulnerabilityFound` fired

1. Confirm the CVE is real and applicable — Trivy's own report includes the CVE ID; cross-check
   against the vendor's own advisory for whether the vulnerable code path is actually reachable
   in how this platform uses the package (not every CVE in a dependency tree is exploitable in
   every consumer's usage).
2. If real and reachable: this is a rebuild-and-redeploy problem, not a runtime-mitigation one — a
   patched base image or dependency bump, rebuilt through the same signed/attested pipeline
   (`docs/signing-guide.md`), is the actual fix. There is no "patch it in place" path in an
   immutable-infrastructure platform (`platform-standards.md` Section 1, principle 6).
3. If the fix isn't available yet: this is exactly what `docs/exception-process.md`'s
   time-boxed, reviewed exception mechanism is *not* for (that's for policy exemptions, not
   unresolved CVEs) — instead, this is a tracked risk-acceptance decision, recorded the same way
   `platform-standards.md` Section 10 already requires for CI-blocked CVEs: "a
   genuinely-accepted-risk CVE gets an ADR ... and an explicit, time-boxed `.trivyignore` entry
   referencing that ADR's number, never a silent suppression."

## `Warning-Kyverno-PolicyViolationsHigh` fired

Usually means either a genuinely broken deploy attempt (check the most recent change to
`k8s/overlays/<env>` or the GitOps repo) or a policy that's about to need a
`docs/exception-process.md` exception for a real, legitimate case the policy didn't anticipate —
distinguish by reading the specific `PolicyReport` entries, not just the alert's count.

## Post-incident

Every incident this phase's tooling catches is, by construction, a case where an earlier layer
(image verification, admission policy, or the vulnerability scan) either wasn't yet in place or
didn't cover the specific gap — the post-incident review's job is identifying which, and whether
closing that gap belongs in `docs/policy-guide.md` (a new or tightened Kyverno policy),
`docs/sbom-guide.md`/`docs/signing-guide.md` (a supply-chain gap), or Falco's own custom-rule
backlog (explicitly out of this phase's scope — "no custom application rules yet" — but exactly
the kind of finding that justifies writing one in a future phase).
