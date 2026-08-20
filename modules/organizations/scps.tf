# Service Control Policies — org-wide guardrails, enforced regardless of any individual account's
# own IAM policies (platform-standards.md Section 1, principle 8: least privilege; principle 9:
# zero trust — an SCP is the one control an over-permissioned IAM role inside a member account
# still can't bypass).

data "aws_iam_policy_document" "deny_leave_organization" {
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_leave_organization" {
  name        = "deny-leave-organization"
  description = "Prevents any member account from removing itself from the organization."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_leave_organization.json
  tags        = merge(var.tags, { Application = "organizations", Purpose = "scp-deny-leave-organization" })
}

data "aws_iam_policy_document" "deny_root_user" {
  statement {
    sid       = "DenyRootUserActions"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
}

resource "aws_organizations_policy" "deny_root_user" {
  name        = "deny-root-user-actions"
  description = "Denies all actions by the root user in every member account — every real operation goes through IAM Identity Center or an assumed role, never the root credentials, per platform-standards.md Section 1 (no long-lived static credentials)."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_root_user.json
  tags        = merge(var.tags, { Application = "organizations", Purpose = "scp-deny-root-user" })
}

data "aws_iam_policy_document" "require_imds_v2" {
  statement {
    sid       = "DenyEC2LaunchWithoutIMDSv2"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringNotEquals"
      variable = "ec2:MetadataHttpTokens"
      values   = ["required"]
    }
  }
}

resource "aws_organizations_policy" "require_imds_v2" {
  name        = "require-imds-v2"
  description = "Blocks launching an EC2 instance (including EKS-managed node group instances) without IMDSv2 enforced — closes the SSRF-to-instance-metadata attack class IMDSv1 permits."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.require_imds_v2.json
  tags        = merge(var.tags, { Application = "organizations", Purpose = "scp-require-imds-v2" })
}

data "aws_iam_policy_document" "deny_outside_approved_regions" {
  statement {
    sid    = "DenyOutsideApprovedRegions"
    effect = "Deny"
    not_actions = [
      # Global-service actions exempted outright — these have no meaningful "region" to restrict
      # and denying them breaks IAM/Organizations/Route53/Support/billing entirely.
      "iam:*",
      "organizations:*",
      "route53:*",
      "route53domains:*",
      "support:*",
      "budgets:*",
      "sts:*",
      "cloudfront:*",
      "waf:*",
      "wafv2:*",
      "acm:*", # ACM certs for CloudFront must be requested in us-east-1 — see global_service_regions
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = concat(var.approved_regions, var.global_service_regions)
    }
  }
}

resource "aws_organizations_policy" "deny_outside_approved_regions" {
  name        = "deny-outside-approved-regions"
  description = "Restricts resource creation to ${join(", ", var.approved_regions)} plus the global-service regions ${join(", ", var.global_service_regions)} — prevents both accidental cross-region resource sprawl and a compromised-credential blast radius spreading to unmonitored regions."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_outside_approved_regions.json
  tags        = merge(var.tags, { Application = "organizations", Purpose = "scp-deny-outside-approved-regions" })
}

data "aws_iam_policy_document" "deny_disable_security_services" {
  statement {
    sid    = "DenyDisableCloudTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyDisableConfig"
    effect = "Deny"
    actions = [
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyDisableGuardDuty"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:UpdateDetector",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "deny_disable_security_services" {
  name        = "deny-disable-security-services"
  description = "Prevents CloudTrail/Config/GuardDuty from being stopped or deleted from within a member account — these are organization-delegated (modules/cloudtrail, modules/config, modules/security) and administered only from the security account."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.deny_disable_security_services.json
  tags        = merge(var.tags, { Application = "organizations", Purpose = "scp-deny-disable-security-services" })
}

# --- Attachments -----------------------------------------------------------------------------
# Baseline (leave-org, root-user) applies everywhere, no exceptions.
resource "aws_organizations_policy_attachment" "deny_leave_organization" {
  for_each  = local.ou_ids
  policy_id = aws_organizations_policy.deny_leave_organization.id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "deny_root_user" {
  for_each  = local.ou_ids
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = each.value
}

# Region restriction and IMDSv2 apply to Workloads (the accounts actually running EC2/EKS compute)
# — Security and Infrastructure OUs run comparatively little compute and, for Security specifically,
# may need Security Hub's org-wide aggregation calls into other regions, so they're not blanket-
# restricted here.
resource "aws_organizations_policy_attachment" "deny_outside_approved_regions_workloads" {
  policy_id = aws_organizations_policy.deny_outside_approved_regions.id
  target_id = local.ou_ids["workloads"]
}

resource "aws_organizations_policy_attachment" "require_imds_v2_workloads" {
  policy_id = aws_organizations_policy.require_imds_v2.id
  target_id = local.ou_ids["workloads"]
}

# Security-service tamper protection applies to Workloads and Infrastructure — explicitly NOT to
# the Security OU itself, since that account is where these services are legitimately administered.
resource "aws_organizations_policy_attachment" "deny_disable_security_services_workloads" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = local.ou_ids["workloads"]
}

resource "aws_organizations_policy_attachment" "deny_disable_security_services_infrastructure" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = local.ou_ids["infrastructure"]
}
