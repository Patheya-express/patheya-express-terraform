variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "environment_tier" {
  type = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment_tier)
    error_message = "environment_tier must be one of: development, staging, production."
  }
}

variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "storage_class_name" {
  description = "From module.eks_addons's default_storage_class — Trivy Operator's optional report-cache PVC, if ever enabled, would reuse it. Not used by Kyverno/Falco, which are stateless."
  type        = string
}

variable "ecr_registry_host" {
  description = <<-EOT
    <shared-services-account-id>.dkr.ecr.<region>.amazonaws.com — the ECR module (modules/ecr)
    lives in the shared-services account (cloud-architecture-blueprint.md Section 2's account
    table), so this is supplied as a tfvar rather than a cross-account terraform_remote_state
    read, matching the exact pattern environments/production/platform already uses for
    apex_zone_id/apex_certificate_arn. Scopes Kyverno's "approved registries" policy
    (policies-baseline.tf) to exactly this registry, patheya-express/* repositories only.
  EOT
  type        = string
}

variable "cosign_oidc_issuer" {
  description = "Sigstore keyless-signing OIDC issuer — GitHub Actions' own issuer, matching cloud-architecture-blueprint.md Section 9's \"cosign sign (keyless, OIDC-based)\" and ADR-006's GitHub Actions decision. No CI exists yet (this phase explicitly excludes it) — this is the trust anchor a future CI pipeline's signatures must present."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "cosign_certificate_identity_regexp" {
  description = <<-EOT
    Sigstore certificate-identity pattern (Fulcio cert SAN) a valid signature must match —
    scoped to the backend/frontend repos' GitHub Actions workflows, any workflow file under those
    repos' .github/workflows/, main branch only. Deliberately still a regexp across two repos and
    "any workflow file" rather than the exact single filename+repo Phase 7's own doc comment
    anticipated narrowing to "once CI exists" — Phase 8 (docs/signing-guide.md) names the two real
    workflow files (patheya-express-platform's `backend-release.yml`, frontend's
    `docker-publish.yml`); this policy is intentionally left one notch broader (matching either
    file in either repo, not each pinned individually) so that renaming a workflow file doesn't
    require a Terraform change in lock-step — the repo + branch scoping is the real security
    boundary, the exact filename is not.
    Corrected during Phase 8 from this variable's original default, which had two real bugs
    verified against the GitHub API: (1) the org segment was "patheya-express" (all lowercase) —
    the real, GitHub-registered login is "Patheya-express" (capital P), and this regexp is matched
    byte-for-byte against the Fulcio certificate's SAN, which GitHub populates from the token's
    real (correctly-cased) `repository` claim, so the lowercase version could never have matched a
    real signature; (2) the frontend repo segment was "patheya-express-frontend" — the frontend
    application's actual GitHub repository is named "frontend" (confirmed via `git remote -v` and
    the GitHub API), not "patheya-express-frontend" (that string is only the pnpm workspace's
    package name, `@patheya-express-frontend/source`, never the repository name).
  EOT
  type        = string
  default     = "^https://github.com/Patheya-express/(patheya-express-platform|frontend)/\\.github/workflows/.+@refs/heads/main$"
}

variable "alertmanager_endpoint" {
  description = "From module.observability's alertmanager_service_dns — Falco alerts route here via falcosidekick, reusing Phase 5's Alertmanager rather than building a second notification pipeline."
  type        = string
}

variable "kyverno_policy_mode" {
  description = <<-EOT
    Enforce | Audit, applied to every baseline ClusterPolicy's non-excluded namespaces
    (policies-baseline.tf). Defaults to "Enforce" for patheya-backend/patheya-frontend only —
    every platform namespace this repository already manages (kube-system, argocd, monitoring,
    logging, tracing, observability, external-secrets, cert-manager, ingress-nginx,
    data-platform, kyverno, trivy-system, falco) is excluded from these policies entirely, not
    merely set to Audit, because several (Karpenter, NGINX, cert-manager, kube-prometheus-stack,
    Loki, Tempo, the OTel Collector) run as their own upstream chart's default securityContext,
    which this phase did not audit line-by-line and has no authority to change without
    redesigning those charts' values (explicitly out of scope). See docs/policy-guide.md.
  EOT
  type        = string
  default     = "Enforce"

  validation {
    condition     = contains(["Enforce", "Audit"], var.kyverno_policy_mode)
    error_message = "kyverno_policy_mode must be Enforce or Audit."
  }
}

variable "image_verification_policy_mode" {
  description = "Enforce | Audit for the Cosign signature + SBOM attestation verification policies specifically (policies-image-verification.tf) — separate from kyverno_policy_mode because this is the one policy this phase's OBJECTIVE explicitly requires at Enforce: \"Nothing deployed after this phase should be able to bypass image verification.\" Still scoped to patheya-backend/patheya-frontend only."
  type        = string
  default     = "Enforce"

  validation {
    condition     = contains(["Enforce", "Audit"], var.image_verification_policy_mode)
    error_message = "image_verification_policy_mode must be Enforce or Audit."
  }
}
