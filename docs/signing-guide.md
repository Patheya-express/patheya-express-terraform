# Signing guide

Cosign keyless signing — prepared in this phase, **no CI implementation** (this phase's explicit
Section 3 scope: "No CI implementation yet"). This document is what a future CI phase's
`.github/workflows/*.yml` needs to satisfy for its signatures to actually pass
`modules/supply-chain-security`'s `verify-image-signatures` policy.

## Why keyless, not a static key pair

`cloud-architecture-blueprint.md` Section 9/11: "cosign sign (keyless, OIDC-based) — no signing
key to leak." A static cosign key pair is a long-lived secret that would need its own rotation
policy, its own Secrets Manager entry, and its own blast-radius story if it ever leaked. Keyless
signing has none of that: GitHub Actions' own OIDC token (already how this platform authenticates
CI to AWS, per ADR-006) is exchanged for a short-lived certificate from Sigstore's public Fulcio
CA, used to sign, and immediately discarded — there is no key to steal because no long-lived key
ever exists.

## What a future CI workflow must do

```yaml
# Illustrative shape only — the actual workflow file doesn't exist yet (a future phase's job).
permissions:
  id-token: write   # required for keyless signing — this is what lets cosign request a Fulcio certificate using the workflow's own OIDC identity
  contents: read
  packages: write

steps:
  - run: cosign sign --yes ${{ env.ECR_REGISTRY }}/patheya-express/api-gateway@${{ steps.build.outputs.digest }}
```

The `--yes` flag skips the interactive confirmation prompt (non-interactive CI); `cosign sign`
with no `--key` flag is what triggers keyless mode automatically once `id-token: write` is
granted. The resulting signature, certificate, and Rekor transparency-log entry are pushed to ECR
as an OCI artifact alongside the image itself — no separate signature store to provision (this is
exactly why "OCI artifact support," this task's Section 4, needed no new Terraform resource: ECR
already stores any OCI artifact type natively).

## Trust anchor this platform verifies against

`modules/supply-chain-security`'s `verify-image-signatures` policy checks two things about the
Fulcio certificate embedded in the signature:

| Field | Value | Why |
| --- | --- | --- |
| `issuer` | `https://token.actions.githubusercontent.com` | GitHub Actions' own OIDC issuer — a signature minted by any other OIDC provider is rejected |
| `subjectRegExp` | `^https://github.com/patheya-express/(patheya-express-platform\|patheya-express-frontend)/\.github/workflows/.+@refs/heads/main$` | Matches any workflow file under either application repo's `.github/workflows/`, on `main` only — a signature from a fork, a feature branch, or an unrelated repo is rejected |

**Narrow this once the real workflow file is named.** The regexp above is deliberately broad
(`.+` for the workflow filename) because no CI workflow has been written yet — the moment it is,
change `subjectRegExp` to the exact filename (e.g.
`.../\.github/workflows/build-and-push\.yml@refs/heads/main$`) so a signature from some other,
unrelated workflow in the same repo can't satisfy this policy by accident.

## SBOM attestation — the second artifact CI must produce

See `docs/sbom-guide.md` — `cosign attest` (not `cosign sign`) is the command that attaches a
CycloneDX SBOM as a verifiable predicate, checked by the separate `verify-sbom-attestation`
policy (Audit-only today; see that policy's own comment for why).
