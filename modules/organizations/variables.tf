variable "tags" {
  description = "Mandatory tag map — pass through module.shared.tags from the calling environment."
  type        = map(string)
}

variable "management_account_email" {
  description = "Root/management account email — informational only (the management account itself is the pre-existing, manually-created account this configuration runs from; Terraform never creates it). Used purely for output/documentation clarity."
  type        = string
}

variable "member_accounts" {
  description = <<-EOT
    One entry per member account this org creates (cloud-architecture-blueprint.md Section 2's six
    non-management accounts: security, shared-services, development, staging, production, dr).
    `email` must be an email address never used for any other AWS account (AWS-wide uniqueness
    requirement) — a "+" alias off a domain-owned mailbox the platform team controls is the
    standard pattern, e.g. "aws-security@patheyaexpress.com".
  EOT
  type = map(object({
    email = string
    ou    = string # one of: security, infrastructure, workloads — see main.tf's OU structure
  }))

  validation {
    condition = alltrue([
      for k, v in var.member_accounts : contains(["security", "infrastructure", "workloads"], v.ou)
    ])
    error_message = "Each member account's ou must be one of: security, infrastructure, workloads."
  }
}

variable "approved_regions" {
  description = "Regions member accounts may operate in — enforced by the deny-outside-approved-regions SCP. ap-south-1 (primary) and ap-southeast-1 (DR) per the blueprint's Section 2; us-east-1 is required for several genuinely-global AWS service control planes (ACM for CloudFront, IAM, Route53, Organizations itself) and is allow-listed for those service calls only, not for general resource creation."
  type        = list(string)
  default     = ["ap-south-1", "ap-southeast-1"]
}

variable "global_service_regions" {
  description = "Regions exempted from the region-restriction SCP because the AWS services involved are inherently global and only expose an API endpoint in these regions."
  type        = list(string)
  default     = ["us-east-1"]
}

variable "enable_identity_center" {
  description = <<-EOT
    IAM Identity Center (AWS SSO) cannot be created via Terraform — it must be manually enabled
    once, in the AWS Console or via `aws sso-admin` CLI, in the management account, before this
    module can manage anything against it (see README.md's manual-prerequisite note). Defaults to
    false so a fresh `terraform apply` of this module never fails on a missing SSO instance; set
    to true only after the manual enablement step is complete.
  EOT
  type        = bool
  default     = false
}

variable "identity_center_group_ids" {
  description = "Identity Store group IDs (from the manually-enabled Identity Center instance) to assign permission sets to — keyed by role name (platform-administrator, developer, read-only, security-auditor, and devqa-workload-operator when enable_devqa_temp_operator_permission_set is true). Only read when enable_identity_center is true."
  type        = map(string)
  default     = {}
}

variable "enable_devqa_temp_operator_permission_set" {
  description = <<-EOT
    false (default) — creates none of the DevQAWorkloadOperator permission-set resources in
    identity-center.tf, and a plain `terraform apply` of this module is completely unaffected by
    their existence in the source file. true additionally creates and assigns that permission
    set, to the Security account only, as the approved compensating control for temporarily
    hosting environments/development-temp's compute there (Phase 1 §3, Phase 1.5 §5). Only
    meaningful when enable_identity_center is also true.
  EOT
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  description = "Monthly budget limit (USD) per account, keyed by account alias — matches the growth-tier estimates in cloud-architecture-blueprint.md Section 13. A sane starting default per account for the \"launch\" tier; revisit at each growth-tier transition (platform-standards.md Section 20)."
  type        = map(number)
  default = {
    security          = 200
    "shared-services" = 500
    development       = 800
    staging           = 1200
    production        = 5000
    dr                = 1000
  }
}

variable "budget_notification_emails" {
  description = "Email addresses notified at 50%/80%/100% of each account's budget (platform-standards.md Section 20)."
  type        = list(string)
}
