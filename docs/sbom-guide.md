# SBOM guide

Prepared this phase — generation is CI work (out of scope, no GitHub Actions yet). This document
is what a future CI pipeline runs, and what's already built to store and (eventually) verify the
result.

## Format: CycloneDX, with SPDX as the documented alternative

CycloneDX is the primary format `verify-sbom-attestation`'s predicate type
(`https://cyclonedx.org/bom`) checks for — chosen because it's Syft's (and most container-focused
SBOM tooling's) default, and because Kyverno's attestation-type matching is a literal string
match against the predicate type a `cosign attest` call declares, so the platform needs exactly
one canonical choice, not "either is fine" (this task's Section 4 names both CycloneDX and SPDX;
supporting both as *equally valid* predicate types would mean the verification policy has to
accept either, doubling the attack surface for what counts as "a real SBOM" for no corresponding
benefit at this platform's scale). SPDX remains a documented, supported *output* format — `syft`
can emit either — but only CycloneDX is what this platform's Kyverno policy currently verifies
against. Revisit only if a specific compliance requirement (e.g., an enterprise customer
contractually requiring SPDX) makes accepting both worth the doubled verification surface.

## What a future CI workflow must do

```bash
# Generate
syft <ecr-registry>/patheya-express/api-gateway@sha256:<digest> -o cyclonedx-json > sbom.cdx.json

# Attach as a verifiable, signed attestation (not just an unsigned artifact sitting next to the image)
cosign attest --yes \
  --predicate sbom.cdx.json \
  --type cyclonedx \
  <ecr-registry>/patheya-express/api-gateway@sha256:<digest>
```

`cosign attest` (not `cosign sign`) — the distinction matters: `sign` produces a bare signature
over the image digest; `attest` produces a signed **statement about** the image (the SBOM
predicate), independently verifiable and independently toggleable from the image signature
itself. Same keyless OIDC identity as `docs/signing-guide.md`'s image signing — one CI identity,
two different claims made about the same image.

## Storage: OCI artifacts in ECR — no new infrastructure

`cosign attest`'s output is pushed to the same ECR repository the image itself lives in, as an
OCI artifact referencing the image's digest — this task's Section 4 "OCI artifact support" is
satisfied entirely by ECR's own native OCI-artifact support (already true of every ECR repository
`modules/ecr` created in Phase 2), not a new Terraform resource. A separate SBOM storage bucket
would be a second place to keep in sync with the image it describes; a digest-addressed OCI
artifact in the same repository can never drift from the image it's attesting to.

## Verification: prepared, Audit-only

`modules/supply-chain-security`'s `verify-sbom-attestation` `ClusterPolicy` checks for a
CycloneDX attestation matching the same keyless identity as image signing — deliberately
**Audit-only**, even in production, unlike `verify-image-signatures`. See that policy's own
comment in `policies-image-verification.tf` for why: Enforcing an SBOM check before any pipeline
has ever produced an SBOM would be indistinguishable from the image-signature policy's own
Enforce block (nothing could ever deploy either way) — this policy's job today is to make the SBOM
gap *visible* in `PolicyReport`s the moment signing exists but SBOM attestation doesn't yet, not
to add a second identical hard block. Revisit once CI reliably produces both artifacts together.

## Verifying an SBOM attestation by hand

```bash
cosign verify-attestation \
  --type cyclonedx \
  --certificate-identity-regexp '^https://github.com/patheya-express/patheya-express-platform/\.github/workflows/.+@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <ecr-registry>/patheya-express/api-gateway@sha256:<digest> | jq -r '.payload' | base64 -d | jq .
```
