variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  description = "From module.shared.name_prefix — e.g. \"patheya-production\"."
  type        = string
}

variable "github_organization" {
  description = <<-EOT
    GitHub organization/user that owns the repositories allowed to assume roles in this account.
    MUST match the organization's real GitHub login byte-for-byte, including case — AWS's
    `StringLike` condition on the `token.actions.githubusercontent.com:sub` claim is a literal
    string comparison, not routed through GitHub's own case-insensitive URL handling the way a
    `git clone`/browser URL would be. Confirmed via the GitHub API
    (`GET /repos/Patheya-express/patheya-express-platform` -> `owner.login`) during Phase 8: the
    real login is "Patheya-express" (capital P), not the all-lowercase "patheya-express" this
    default held before Phase 8 — a real, load-bearing bug fixed here (every prior OIDC trust
    policy generated from this module's old default would silently never match a real GitHub
    Actions token). Kept as a variable, not hardcoded, in case a future account genuinely needs a
    different org — but the default is now the org's actual, verified login.
  EOT
  type        = string
  default     = "Patheya-express"
}

variable "github_repositories" {
  description = "Repository names (within github_organization) whose GitHub Actions workflows may assume the Terraform CI role in this account — least privilege at the repo level, not org-wide."
  type        = list(string)
  default     = ["patheya-express-terraform"]
}

variable "terraform_role_allowed_branches" {
  description = "Git refs (branch or tag patterns, GitHub OIDC claim format) allowed to assume the Terraform CI role — restricts `terraform apply`-capable identity to protected branches only, never an arbitrary feature branch."
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider in this account. Each AWS account needs its own OIDC provider object (IAM is account-scoped) — true in every account this module is called in, unless a prior call in the same account (unlikely, but possible if this module is invoked twice) already created one."
  type        = bool
  default     = true
}

variable "backend_github_repository" {
  description = <<-EOT
    The backend application repository's real GitHub name — confirmed via `git remote -v` /
    the GitHub API during Phase 8 to be "patheya-express-platform" (the repo backing this very
    Terraform configuration's sibling application), NOT "patheya-express-backend" as
    platform-standards.md Section 2's repository table names it. That table entry is aspirational
    documentation describing the intended repo purpose; this variable reflects the real,
    GitHub-registered name a trust policy must match. Revisit this variable's default (and the
    Section 2 table, via a docs PR) only if the repository is ever actually renamed.
  EOT
  type        = string
  default     = "patheya-express-platform"
}

variable "frontend_github_repository" {
  description = <<-EOT
    The frontend application repository's real GitHub name — confirmed via `git remote -v` / the
    GitHub API during Phase 8 to be "frontend" (a bare name — the pnpm workspace's package name
    "@patheya-express-frontend/source" is where the "patheya-express-frontend" naming assumption
    baked into Phase 7's `cosign_certificate_identity_regexp` default came from, but the actual
    GitHub repository is just "frontend"). Fixed here rather than propagated further.
  EOT
  type        = string
  default     = "frontend"
}

variable "app_release_allowed_branches" {
  description = <<-EOT
    Git refs allowed to assume the backend/frontend ECR-push roles — deliberately narrower than
    `terraform_role_allowed_branches` might ever need to be: platform-standards.md Section 6
    ("Development: Continuous deploy on every merge to main") and Section 10 ("Promotion: an image
    built once is promoted unchanged from dev -> staging -> production, never rebuilt per
    environment") together mean exactly one event ever needs to push an image — a merge to `main`.
    A tag-triggered release workflow re-uses the already-pushed, already-signed image (Section
    10); it never rebuilds, so it never needs this role either. No PR/feature-branch build should
    ever hold ECR push credentials.
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "backend_ecr_repository_arns" {
  description = "From module.ecr.repository_arns[\"api-gateway\"] (this account) — scopes the backend push role to exactly the one ECR repository it publishes to."
  type        = list(string)
}

variable "frontend_ecr_repository_arns" {
  description = "From module.ecr.repository_arns, filtered to the four frontend app repositories (customer-app, partner-app, delivery-app, admin-app) — scopes the frontend push role to exactly those, never api-gateway."
  type        = list(string)
}
