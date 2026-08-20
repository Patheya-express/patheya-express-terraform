# S3 bucket for remote state — platform-standards.md Section 9: one bucket per AWS account
# (patheya-express-terraform-state-<account-id>), never shared across accounts, so dev/staging/
# prod state can never cross-contaminate even via misconfiguration.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "patheya-express-terraform-state-${var.account_id}"

  # Deliberately never destroyed by a routine `terraform destroy` in this configuration — the
  # bucket holds every other configuration's state. A real teardown of an account is a deliberate,
  # separate, manually-confirmed action, not something a bootstrap re-apply should ever risk.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256), not SSE-KMS, deliberately: the KMS module's keys are themselves created via the
# remote backend this bucket provides — encrypting the bootstrap bucket with a KMS key would be a
# second chicken-and-egg dependency on top of the first. AES256 is still real encryption at rest;
# this is a documented bootstrap-ordering constraint, not a security gap.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

# DynamoDB table for S3-backend state locking (Terraform 1.9.x — native S3 lockfile locking
# arrived in 1.10+; pinned at 1.9.8 per versions.tf, so DynamoDB locking is the correct mechanism
# platform-wide, not a legacy leftover).
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "patheya-express-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
