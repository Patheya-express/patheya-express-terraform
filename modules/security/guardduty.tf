resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true # ready for Phase 3's EKS clusters — GuardDuty's EKS Audit Log Monitoring needs no further config once nodes exist
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(var.tags, { Application = "security", Purpose = "guardduty-detector" })
}

# Management account only — designates the security account as the org-wide delegated admin.
resource "aws_guardduty_organization_admin_account" "this" {
  count = var.delegate_admin_account_id != null ? 1 : 0

  admin_account_id = var.delegate_admin_account_id
}

# Security account only (as delegated admin) — auto-enrolls every current and future org member.
resource "aws_guardduty_organization_configuration" "this" {
  count = var.is_delegated_admin_account && var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id

  auto_enable_organization_members = "ALL"

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        # Provider schema quirk (aws_guardduty_organization_configuration, confirmed via
        # `terraform validate`): every sibling block here uses `auto_enable`, but this specific
        # nested block's argument is named `enable` — not a copy-paste inconsistency on our part,
        # the AWS provider's schema for this one nested block genuinely differs from its siblings.
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }
}
