# AWS Config's managed REQUIRED_TAGS rule accepts at most 6 tag keys per rule instance — the
# fourteen mandatory tags (platform-standards.md Section 5) are split into three rule instances
# rather than silently only checking the first six.
locals {
  tag_chunks = chunklist(var.mandatory_tag_keys, 6)
}

resource "aws_config_config_rule" "required_tags" {
  count = length(local.tag_chunks)

  name = "${var.name_prefix}-required-tags-${count.index + 1}"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode(merge([
    for i, key in local.tag_chunks[count.index] : { "tag${i + 1}Key" = key }
  ]...))

  depends_on = [aws_config_configuration_recorder.this]

  tags = merge(var.tags, { Application = "config", Purpose = "required-tags-compliance-check-${count.index + 1}" })
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "${var.name_prefix}-s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "s3-public-read-check" })
}

resource "aws_config_config_rule" "s3_bucket_ssl_requests_only" {
  name = "${var.name_prefix}-s3-bucket-ssl-requests-only"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "s3-tls-enforcement-check" })
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${var.name_prefix}-encrypted-volumes"
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "ebs-encryption-check" })
}

resource "aws_config_config_rule" "root_account_mfa_enabled" {
  name = "${var.name_prefix}-root-account-mfa-enabled"
  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "root-mfa-check" })
}

resource "aws_config_config_rule" "iam_user_no_policies_check" {
  name = "${var.name_prefix}-iam-user-no-policies-check"
  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_NO_POLICIES_CHECK"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "iam-user-inline-policy-check-should-find-zero-users" })
}

resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  name = "${var.name_prefix}-vpc-flow-logs-enabled"
  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder.this]
  tags       = merge(var.tags, { Application = "config", Purpose = "vpc-flow-logs-check" })
}
