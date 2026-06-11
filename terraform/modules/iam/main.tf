# ── Glue Execution Role ───────────────────────────────────────────────────────

resource "aws_iam_role" "glue_execution" {
  name        = "${var.project_name}-glue-execution"
  description = "Assumed by AWS Glue ETL jobs - read/write lakehouse and assets buckets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.aws_account_id }
      }
    }]
  })

  tags = merge(var.tags, { Service = "glue", Role = "execution" })
}

# S3 access — lakehouse (rw) and glue-assets (rw); raw (r for ingestion job)
resource "aws_iam_policy" "glue_s3" {
  name        = "${var.project_name}-glue-s3"
  description = "Scoped S3 access for Glue ETL jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LakehouseReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:GetObjectVersion", "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          var.lakehouse_bucket_arn,
          "${var.lakehouse_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      },
      {
        Sid    = "GlueAssetsReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          var.glue_assets_bucket_arn,
          "${var.glue_assets_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      },
      {
        Sid    = "RawBucketRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          var.raw_bucket_arn,
          "${var.raw_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      }
    ]
  })
}

# KMS — decrypt and generate data keys for SSE-KMS reads/writes
resource "aws_iam_policy" "glue_kms" {
  name        = "${var.project_name}-glue-kms"
  description = "KMS usage rights for Glue ETL jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "KmsUsage"
      Effect = "Allow"
      Action = [
        "kms:Decrypt", "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey"
      ]
      Resource = [var.kms_key_arn]
    }]
  })
}

# Glue catalog — read/write tables and partitions; no DDL on silver/gold (LF handles that)
resource "aws_iam_policy" "glue_catalog" {
  name        = "${var.project_name}-glue-catalog"
  description = "Glue Data Catalog access for ETL jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CatalogAccess"
      Effect = "Allow"
      Action = [
        "glue:GetDatabase", "glue:GetDatabases",
        "glue:GetTable", "glue:GetTables", "glue:GetPartition", "glue:GetPartitions",
        "glue:UpdateTable", "glue:BatchCreatePartition", "glue:BatchDeletePartition",
        "glue:CreateTable"
      ]
      Resource = [
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/${var.project_name}_*",
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}_*/*"
      ]
    }]
  })
}

# CloudWatch Logs — job log streaming
resource "aws_iam_policy" "glue_logs" {
  name        = "${var.project_name}-glue-logs"
  description = "CloudWatch Logs write access for Glue job output"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LogStreaming"
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup", "logs:CreateLogStream",
        "logs:PutLogEvents", "logs:DescribeLogStreams"
      ]
      Resource = [
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws-glue/jobs/*",
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws-glue/crawlers*"
      ]
    }]
  })
}

# CloudWatch Metrics — custom job metrics
resource "aws_iam_policy" "glue_metrics" {
  name        = "${var.project_name}-glue-metrics"
  description = "CloudWatch custom metrics for Glue jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutMetrics"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
      Condition = {
        StringEquals = { "cloudwatch:namespace" = "${var.project_name}/GlueJobs" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_execution" {
  for_each = {
    s3      = aws_iam_policy.glue_s3.arn
    kms     = aws_iam_policy.glue_kms.arn
    catalog = aws_iam_policy.glue_catalog.arn
    logs    = aws_iam_policy.glue_logs.arn
    metrics = aws_iam_policy.glue_metrics.arn
    # AWS managed policy for Glue control-plane operations
    managed = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  }

  role       = aws_iam_role.glue_execution.name
  policy_arn = each.value
}

# ── Glue Crawler Role ─────────────────────────────────────────────────────────
# More restricted than the execution role — read-only S3, catalog write only.

resource "aws_iam_role" "glue_crawler" {
  name        = "${var.project_name}-glue-crawler"
  description = "Assumed by Glue crawlers - read S3, write Glue catalog"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.aws_account_id }
      }
    }]
  })

  tags = merge(var.tags, { Service = "glue", Role = "crawler" })
}

resource "aws_iam_policy" "crawler_s3" {
  name        = "${var.project_name}-crawler-s3"
  description = "Read-only S3 access for Glue crawlers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CrawlerS3Read"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        var.lakehouse_bucket_arn,
        "${var.lakehouse_bucket_arn}/*"
      ]
      Condition = {
        StringEquals = { "aws:RequestedRegion" = var.aws_region }
      }
    }]
  })
}

resource "aws_iam_policy" "crawler_catalog" {
  name        = "${var.project_name}-crawler-catalog"
  description = "Glue catalog write access for crawlers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CrawlerCatalogWrite"
      Effect = "Allow"
      Action = [
        "glue:GetDatabase", "glue:GetTable", "glue:GetTables",
        "glue:CreateTable", "glue:UpdateTable", "glue:DeleteTable",
        "glue:BatchCreatePartition", "glue:BatchDeletePartition",
        "glue:GetPartition", "glue:UpdatePartition"
      ]
      Resource = [
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:catalog",
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:database/${var.project_name}_*",
        "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}_*/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_crawler" {
  for_each = {
    s3      = aws_iam_policy.crawler_s3.arn
    kms     = aws_iam_policy.glue_kms.arn
    catalog = aws_iam_policy.crawler_catalog.arn
    logs    = aws_iam_policy.glue_logs.arn
    managed = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  }

  role       = aws_iam_role.glue_crawler.name
  policy_arn = each.value
}

# ── Step Functions Execution Role ─────────────────────────────────────────────

resource "aws_iam_role" "step_functions" {
  name        = "${var.project_name}-step-functions"
  description = "Assumed by Step Functions state machine - start Glue jobs and crawlers"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:*"
        }
      }
    }]
  })

  tags = merge(var.tags, { Service = "step-functions", Role = "execution" })
}

resource "aws_iam_policy" "step_functions_glue" {
  name        = "${var.project_name}-sfn-glue"
  description = "Allows Step Functions to start and monitor Glue jobs and crawlers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GlueJobControl"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:job/${var.project_name}-*"
        ]
      },
      {
        Sid    = "GlueCrawlerControl"
        Effect = "Allow"
        Action = ["glue:StartCrawler", "glue:GetCrawler", "glue:StopCrawler"]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:crawler/${var.project_name}-*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "step_functions_logs" {
  name        = "${var.project_name}-sfn-logs"
  description = "CloudWatch Logs delivery for Step Functions execution history"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SfnLogDelivery"
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery", "logs:GetLogDelivery",
        "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries", "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "step_functions_sns" {
  name        = "${var.project_name}-sfn-sns"
  description = "Allows Step Functions to publish pipeline alerts to SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SnsPublish"
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = ["arn:aws:sns:${var.aws_region}:${var.aws_account_id}:${var.project_name}-*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "step_functions" {
  for_each = {
    glue = aws_iam_policy.step_functions_glue.arn
    logs = aws_iam_policy.step_functions_logs.arn
    sns  = aws_iam_policy.step_functions_sns.arn
  }

  role       = aws_iam_role.step_functions.name
  policy_arn = each.value
}

# ── Lake Formation Service Role ───────────────────────────────────────────────

resource "aws_iam_role" "lake_formation" {
  name        = "${var.project_name}-lake-formation"
  description = "Assumed by Lake Formation to register and access S3 lakehouse locations"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lakeformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.aws_account_id }
      }
    }]
  })

  tags = merge(var.tags, { Service = "lake-formation", Role = "service" })
}

resource "aws_iam_policy" "lake_formation_s3" {
  name        = "${var.project_name}-lf-s3"
  description = "S3 read access for Lake Formation to register lakehouse locations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LFLocationAccess"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [
        var.lakehouse_bucket_arn,
        "${var.lakehouse_bucket_arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lake_formation" {
  role       = aws_iam_role.lake_formation.name
  policy_arn = aws_iam_policy.lake_formation_s3.arn
}
