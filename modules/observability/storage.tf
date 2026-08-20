# S3-backed object storage for Loki (log chunks/index) and Tempo (trace blocks) — matches
# "production-first" (this task's quality bar): PVC-only storage doesn't scale for log/trace
# volume the way it does for Prometheus's much smaller, short-retention TSDB (which does stay on
# the existing gp3 StorageClass — storage.tf's PVCs are configured in the Helm values templates,
# not here).

resource "aws_s3_bucket" "loki" {
  bucket = "${var.name_prefix}-loki-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Application = "observability", Purpose = "loki-log-storage" })
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Disabled" # log chunks are immutable and write-once by construction — versioning adds cost with no recovery benefit here
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Retention split: "hot" (Loki's own queryable retention, var.loki_retention_days) is enforced by
# Loki itself (limits_config.retention_period, templates/loki-values.yaml.tpl) — this lifecycle
# rule is the "cold" tier platform-standards.md Section 11 describes for production only
# (30 days hot + 1 year cold), transitioning objects Loki still considers in-retention to cheaper
# storage without deleting them outright.
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "cold-tier"
    status = var.environment_tier == "production" ? "Enabled" : "Disabled"

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "non-production-expiry"
    status = var.environment_tier == "production" ? "Disabled" : "Enabled"

    expiration {
      days = var.loki_retention_days + 3 # small buffer past Loki's own retention so a delayed compaction cycle doesn't race the bucket deleting data Loki still expects
    }
  }
}

resource "aws_s3_bucket" "tempo" {
  bucket = "${var.name_prefix}-tempo-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Application = "observability", Purpose = "tempo-trace-storage" })
}

resource "aws_s3_bucket_versioning" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket                  = aws_s3_bucket.tempo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    id     = "trace-expiry"
    status = "Enabled"

    expiration {
      days = ceil(var.tempo_retention_hours / 24) + 1
    }
  }
}
