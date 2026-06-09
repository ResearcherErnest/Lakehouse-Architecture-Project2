# ── Glue Job Definitions ──────────────────────────────────────────────────────
# All jobs use Glue 4.0 with native Delta Lake support (--datalake-formats delta).
# Glue bookmarks are enabled for idempotent incremental processing.
# max_concurrent_runs = 1 prevents overlapping executions of the same job.

locals {
  # Shared S3 paths injected into every job as default arguments
  common_args = {
    "--datalake-formats"             = "delta"
    "--enable-glue-datacatalog"      = "true"
    "--enable-job-insights"          = "true"
    "--enable-metrics"               = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-bookmark-option"          = "job-bookmark-enable"
    "--TempDir"                      = "s3://${var.glue_assets_bucket_name}/tmp/"
    "--RAW_BUCKET"                   = var.raw_bucket_name
    "--LAKEHOUSE_BUCKET"             = var.lakehouse_bucket_name
    "--BRONZE_PREFIX"                = "bronze"
    "--SILVER_PREFIX"                = "silver"
    "--GOLD_PREFIX"                  = "gold"
    "--CATALOG_DATABASE_BRONZE"      = "${var.project_name}_bronze"
    "--CATALOG_DATABASE_SILVER"      = "${var.project_name}_silver"
    "--CATALOG_DATABASE_GOLD"        = "${var.project_name}_gold"
    "--conf spark.sql.extensions"    = "io.delta.sql.DeltaSparkSessionExtension"
    "--conf spark.sql.catalog.spark_catalog" = "org.apache.spark.sql.delta.catalog.DeltaCatalog"
  }

  # All seven jobs with their script paths and descriptions
  jobs = {
    raw_to_bronze = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/ingestion/raw_to_bronze.py"
      description = "Ingests raw CSV files from landing bucket into Bronze Delta tables"
    }
    products_silver = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/bronze_to_silver/products_silver.py"
      description = "Transforms Bronze products to Silver with SCD Type 2"
    }
    orders_silver = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/bronze_to_silver/orders_silver.py"
      description = "Transforms Bronze orders to Silver with type casting and deduplication"
    }
    order_items_silver = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/bronze_to_silver/order_items_silver.py"
      description = "Transforms Bronze order_items to Silver with validation and line_total derivation"
    }
    daily_revenue_gold = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/silver_to_gold/daily_revenue_gold.py"
      description = "Aggregates daily revenue by department from Silver orders and order_items"
    }
    product_performance_gold = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/silver_to_gold/product_performance_gold.py"
      description = "Computes monthly product performance metrics and department revenue rank"
    }
    customer_orders_gold = {
      script      = "s3://${var.glue_assets_bucket_name}/scripts/silver_to_gold/customer_orders_gold.py"
      description = "Computes customer lifetime value and order frequency metrics"
    }
  }
}

resource "aws_glue_job" "jobs" {
  for_each = local.jobs

  name         = "${var.project_name}-${replace(each.key, "_", "-")}"
  role_arn     = var.glue_execution_role_arn
  description  = each.value.description
  glue_version = "4.0"

  worker_type      = var.worker_type
  number_of_workers = var.num_workers
  timeout          = var.job_timeout_minutes

  command {
    name            = "glueetl"
    script_location = each.value.script
    python_version  = "3"
  }

  default_arguments = local.common_args

  execution_property {
    max_concurrent_runs = 1
  }

  # Encrypt Spark shuffle data and job bookmarks with the CMK
  security_configuration = aws_glue_security_configuration.main.name

  connections = [aws_glue_connection.vpc.name]

  tags = merge(var.tags, { Job = each.key })

  depends_on = [aws_glue_security_configuration.main]
}

# ── Glue Security Configuration ───────────────────────────────────────────────

resource "aws_glue_security_configuration" "main" {
  name = "${var.project_name}-security-config"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.kms_key_arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }
  }
}

# ── Glue VPC Connection ───────────────────────────────────────────────────────
# Attaches Glue jobs to the private VPC so all traffic flows via VPC endpoints.

resource "aws_glue_connection" "vpc" {
  name            = "${var.project_name}-vpc-connection"
  connection_type = "NETWORK"
  description     = "Routes Glue job traffic through private VPC subnets"

  physical_connection_requirements {
    subnet_id              = var.vpc_subnet_ids[0]
    security_group_id_list = [var.glue_security_group_id]
    availability_zone      = data.aws_subnet.first.availability_zone
  }

  tags = var.tags
}

data "aws_subnet" "first" {
  id = var.vpc_subnet_ids[0]
}
