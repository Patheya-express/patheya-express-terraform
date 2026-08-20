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

variable "storage_class_name" {
  description = "From module.eks_addons's default_storage_class — the Redis (ArgoCD's internal cache) StatefulSet's PVC, if enabled, reuses the same gp3 class every other stateful workload uses."
  type        = string
}

variable "gitops_repo_url" {
  description = <<-EOT
    The patheya-express-gitops repository's clone URL — the ONLY repo the root Application
    (bootstrap layer) reads from directly. Placeholder https://github.com/patheya-express/
    patheya-express-gitops.git until that repository has a real remote; see docs/argocd-guide.md.
  EOT
  type        = string
}

variable "backend_repo_url" {
  description = "patheya-express-platform's clone URL — the applications-layer AppProject's sourceRepos allowlist includes this in addition to the gitops repo, since Applications in this layer point directly at its own k8s/overlays (docs/gitops-bootstrap-guide.md explains why, and the migration path once Phase 7's CI/image-promotion pipeline exists)."
  type        = string
}

variable "repo_credentials_secret_arn" {
  description = "From a modules/secrets-manager call in platform/main.tf — an empty container a human populates with a Git deploy key or PAT once the repos have real GitHub remotes. Empty/unset works fine today for local-only repos."
  type        = string
}

variable "admin_rbac_group" {
  description = "IAM Identity Center group name granted role:admin in ArgoCD's own RBAC policy, once Identity Center is enabled (Phase 2's enable_identity_center gate). Null leaves only the built-in local admin account — no group-based admin mapping fabricated against a Identity Center instance that may not exist yet."
  type        = string
  default     = null
}
