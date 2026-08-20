data "aws_iam_policy_document" "key" {
  for_each = var.keys

  # Account root always retains full key management — the standard AWS-recommended baseline
  # statement that prevents a key from ever becoming unmanageable by the account itself.
  statement {
    sid       = "EnableRootAccountFullAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.key_administrators) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministrators"
      effect = "Allow"
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
        "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
        "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = each.value.key_administrators
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.additional_services
    content {
      sid    = "AllowServicePrincipal${replace(title(replace(statement.value, ".", " ")), " ", "")}"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = [statement.value]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  for_each = var.keys

  description             = each.value.description
  enable_key_rotation     = each.value.enable_rotation
  deletion_window_in_days = each.value.deletion_window_days
  policy                  = data.aws_iam_policy_document.key[each.key].json

  tags = merge(var.tags, {
    Application = "kms"
    Purpose     = "encryption-key-${each.key}"
  })
}

resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = "alias/${var.name_prefix}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}
