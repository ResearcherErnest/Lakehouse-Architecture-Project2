# ── Local helpers ─────────────────────────────────────────────────────────────

locals {
  buckets = {
    raw           = "${var.project_name}-raw-${var.aws_account_id}"
    lakehouse     = "${var.project_name}-lakehouse-${var.aws_account_id}"
    glue_assets   = "${var.project_name}-glue-assets-${var.aws_account_id}"
    athena_results = "${var.project_name}-athena-results-${var.aws_account_id}"
  }

  # Buckets that use the CMK for SSE-KMS
  kms_buckets = ["lakehouse", "glue_assets", "athena_results"]
  # Raw bucket uses AES256 — KMS adds latency on high-throughput raw ingestion
  aes_buckets = ["raw"]
}

# ── Bucket resources (one per key in locals.buckets) ─────────────────────────

resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  bucket   = each.value

  tags = merge(var.tags, {
    Name    = each.value
    Purpose = each.key
  })
}

# ── Versioning ────────────────────────────────────────────────────────────────
# Enabled on lakehouse (Delta log relies on consistent object versions) and raw.
# Disabled on glue_assets and athena_results (no need, adds cost).

resource "aws_s3_bucket_versioning" "enabled" {
  for_each = { for k, v in local.buckets : k => v if contains(["raw", "lakehouse"], k) }

  bucket = aws_s3_bucket.buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# ── Server-side encryption ────────────────────────────────────────────────────

resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  for_each = toset(local.kms_buckets)

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aes" {
  for_each = toset(local.aes_buckets)

  bucket = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# ── Block all public access ───────────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "all" {
  for_each = local.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Bucket policies (TLS-only) ────────────────────────────────────────────────

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.buckets[each.key].arn,
          "${aws_s3_bucket.buckets[each.key].arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.all]
}

# ── Lifecycle rules ───────────────────────────────────────────────────────────

# Raw bucket: IA after 30 days, Glacier after 90, abort incomplete MPU after 7
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.buckets["raw"].id

  rule {
    id     = "raw-tiering"
    status = "Enabled"

    filter {}

    transition {
      days          = var.raw_retention_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.raw_glacier_days
      storage_class = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Lakehouse bucket: S3 Intelligent-Tiering on bronze/ prefix
resource "aws_s3_bucket_lifecycle_configuration" "lakehouse" {
  bucket = aws_s3_bucket.buckets["lakehouse"].id

  rule {
    id     = "bronze-intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = "bronze/"
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      # Keep 10 versions for Delta time-travel, expire older ones
      newer_noncurrent_versions = 10
      noncurrent_days           = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Athena results: expire after N days to control cost
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.buckets["athena_results"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = var.athena_results_expiry_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ── EventBridge notification on raw bucket ────────────────────────────────────
# Enables S3-event-driven pipeline triggering (EventBridge module consumes this).

resource "aws_s3_bucket_notification" "raw" {
  bucket      = aws_s3_bucket.buckets["raw"].id
  eventbridge = true
}
