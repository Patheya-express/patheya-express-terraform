variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS control plane + managed node group version. Pinned, never \"latest\" — platform-standards.md Section 9's version-pinning stance applies to the cluster version too, not just Terraform/provider versions."
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  type = string
}

variable "private_app_subnet_ids" {
  description = "From module.vpc (Phase 2) — the cluster's control plane ENIs and every managed/Karpenter-provisioned node live here, never in a public subnet."
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "From module.networking (Phase 2) — the eks-node-sg created in that phase specifically so this phase would attach to an already-reviewed boundary instead of inventing one under deploy pressure (see that module's README)."
  type        = string
}

variable "kms_key_arn" {
  description = "From this environment's own module.kms call (a new \"eks-secrets\" key, added in cluster/main.tf — not retrofitted into Phase 2's existing KMS calls, keeping Phase 2's already-defined state untouched) — used for EKS's native Kubernetes Secrets envelope encryption."
  type        = string
}

variable "endpoint_public_access" {
  description = "true enables a public endpoint restricted to endpoint_public_access_cidrs (still requires SigV4-authenticated kubectl access — this is a network-reachability control, not an authorization bypass). The private endpoint (endpoint_private_access, always true, not configurable) is always available from inside the VPC regardless of this setting."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "Required, no default — a bare aws_eks_cluster default of 0.0.0.0/0 for the public endpoint is exactly the kind of implicit-permissive default platform-standards.md Section 1 (principle 7, security by default) forbids. Set to your office/VPN egress CIDR(s), or []  with endpoint_public_access = false for a fully private cluster reachable only via a bastion/VPN into the VPC."
  type        = list(string)

  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not permitted for the EKS public endpoint — restrict to real, known CIDRs, or set endpoint_public_access = false."
  }
}

variable "system_node_instance_types" {
  description = "On-demand only — this node group exists specifically to host cluster-critical add-ons (CoreDNS, Karpenter itself, the AWS Load Balancer Controller) that must never be evicted by a spot interruption."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_desired_size" {
  type    = number
  default = 3
}

variable "system_node_min_size" {
  type    = number
  default = 3
}

variable "system_node_max_size" {
  type    = number
  default = 3
}

variable "application_node_instance_types" {
  description = "On-demand baseline for application workloads, sized to always cover the HPA minReplicas floor (cloud-architecture-blueprint.md Section 3's Karpenter design) — everything above this floor scales via Karpenter's on-demand and spot NodePools (modules/eks-addons), not by growing this managed node group further."
  type        = list(string)
  default     = ["m6i.xlarge", "m6a.xlarge"]
}

variable "application_node_desired_size" {
  type    = number
  default = 3
}

variable "application_node_min_size" {
  type    = number
  default = 3
}

variable "application_node_max_size" {
  type    = number
  default = 6
}

variable "access_entries" {
  description = <<-EOT
    EKS Access Entries (the modern, Terraform-native replacement for the legacy aws-auth
    ConfigMap — platform-standards.md Section 1 principle 4: this is exactly the kind of
    configuration that belongs in Git, not a ConfigMap someone edited by hand once). Keyed by a
    descriptive name, each maps an IAM principal ARN to one or more AWS-managed EKS access
    policies.
  EOT
  type = map(object({
    principal_arn      = string
    access_policy_arns = list(string)
    kubernetes_groups  = optional(list(string), [])
  }))
  default = {}
}

variable "log_retention_days" {
  type    = number
  default = 90
}
