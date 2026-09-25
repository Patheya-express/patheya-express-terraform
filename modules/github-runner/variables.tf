variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "kms_key_arn" {
  description = "Encrypts the GitHub PAT secret and the runner's CloudWatch log group."
  type        = string
}

variable "permission_boundary_arn" {
  type = string
}

variable "github_repository" {
  description = "owner/repo this runner registers against - scoped to exactly one repository, matching every other GitHub OIDC trust policy in this repository (modules/iam's github_repositories/backend_github_repository/frontend_github_repository)."
  type        = string
  default     = "Patheya-express/patheya-express-terraform"
}

variable "runner_labels" {
  description = "Labels a workflow's `runs-on: [...]` selects this runner by - e.g. [\"self-hosted\", \"production\", \"private-eks\"]."
  type        = list(string)
  default     = ["self-hosted", "production", "private-eks"]
}

variable "runner_image" {
  description = "Container image running the actions-runner agent itself (not application code) - defaults to the widely-used myoung34/github-runner, which handles registration/deregistration lifecycle against a GitHub PAT automatically. Revisit with an internally-built, Trivy-scanned image if this runner becomes a long-term fixture rather than a bootstrap/admin-path tool."
  type        = string
  default     = "myoung34/github-runner:latest"
}

variable "desired_count" {
  description = "1 is sufficient - this runner exists for infrequent Production platform-layer/cluster operations, not high-throughput CI."
  type        = number
  default     = 1
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "log_retention_days" {
  type    = number
  default = 30
}
