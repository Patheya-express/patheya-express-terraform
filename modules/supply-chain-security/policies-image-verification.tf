# The one policy this phase's OBJECTIVE names explicitly: "Nothing deployed after this phase
# should be able to bypass image verification." Enforcement mode is var.image_verification_
# policy_mode (default Enforce), independent of var.kyverno_policy_mode — this is deliberately
# not bundled with policies-baseline.tf's other 13 policies, which all default to the same mode
# together; this one policy's mode is the actual supply-chain security guarantee this phase
# exists to provide and is controlled on its own.
#
# No CI implementation exists yet (explicitly out of this phase's scope — GitHub Actions is a
# future phase). This means: from the moment this policy is Enforce, no image can be deployed
# into patheya-backend/patheya-frontend AT ALL until that future CI phase produces a cosign-
# signed, ECR-pushed image — which is the intended, deliberate gate, not an oversight. See
# docs/signing-guide.md and docs/verification-guide.md.

resource "kubernetes_manifest" "policy_verify_image_signatures" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "verify-image-signatures"
      annotations = {
        "policies.kyverno.io/title"    = "Verify Cosign Keyless Image Signatures"
        "policies.kyverno.io/severity" = "critical"
        "policies.kyverno.io/category" = "Supply Chain Security (SLSA)"
      }
    }
    spec = {
      validationFailureAction = var.image_verification_policy_mode
      background              = false # signature verification is a live, per-request registry call — meaningless to re-evaluate against already-running pods on a schedule the way a static-field policy is
      webhookTimeoutSeconds   = 30    # Sigstore's Fulcio/Rekor round-trip plus the ECR registry call can be slower than Kyverno's 10s default
      rules = [
        {
          name  = "verify-signature-keyless"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          verifyImages = [
            {
              imageReferences = ["${var.ecr_registry_host}/patheya-express/*"]
              attestors = [
                {
                  count = 1
                  entries = [
                    {
                      keyless = {
                        subjectRegExp = var.cosign_certificate_identity_regexp
                        issuer        = var.cosign_oidc_issuer
                        rekor         = { url = "https://rekor.sigstore.dev" }
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

# SBOM attestation verification — a second, independent verifyImages rule checking for a
# cosign-attested CycloneDX SBOM predicate (this task's Section 4), not just a bare signature.
# Kept as its own ClusterPolicy (rather than a second rule in the one above) so the two can be
# toggled to Audit independently — a signed-but-not-yet-SBOM-attested image is a materially
# different, lesser risk than a genuinely unsigned one, and this repository's existing pattern
# (every module here) never merges two independently-toggleable concerns into one resource.
resource "kubernetes_manifest" "policy_verify_sbom_attestation" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "verify-sbom-attestation"
      annotations = {
        "policies.kyverno.io/title"    = "Verify CycloneDX SBOM Attestation"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Supply Chain Security (SLSA)"
      }
    }
    spec = {
      # Audit-only regardless of image_verification_policy_mode, even in production — this task's
      # Section 4 says "prepare" SBOM verification, and Section 3 says the signing side has no CI
      # yet either; Enforcing an SBOM-attestation check before any pipeline has ever produced one
      # would be indistinguishable from Enforcing "nothing may ever deploy," which is already
      # exactly what verify-image-signatures (Enforce by default) achieves on its own. This policy
      # exists to make the SBOM gap visible in PolicyReports the moment signing exists but SBOM
      # attestation doesn't yet — not to add a second identical hard block.
      validationFailureAction = "Audit"
      background              = false
      webhookTimeoutSeconds   = 30
      rules = [
        {
          name  = "verify-sbom-attestation-keyless"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          verifyImages = [
            {
              imageReferences = ["${var.ecr_registry_host}/patheya-express/*"]
              attestations = [
                {
                  type = "https://cyclonedx.org/bom"
                  attestors = [
                    {
                      count = 1
                      entries = [
                        {
                          keyless = {
                            subjectRegExp = var.cosign_certificate_identity_regexp
                            issuer        = var.cosign_oidc_issuer
                            rekor         = { url = "https://rekor.sigstore.dev" }
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}
