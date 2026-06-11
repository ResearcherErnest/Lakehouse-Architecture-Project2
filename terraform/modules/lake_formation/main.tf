# ── Lake Formation Data Lake Settings ─────────────────────────────────────────
# Sets the LF service role and data lake admins.
# The Glue execution role is also added as an admin so it can register
# partitions and manage table metadata without a separate LF grant.
# The current Terraform caller must also be in the list — aws_lakeformation_data_lake_settings
# REPLACES the entire admin list, so omitting the caller locks it out of subsequent LF grants.

data "aws_caller_identity" "current" {}

resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [
    "arn:aws:iam::${var.aws_account_id}:root",
    var.lake_formation_role_arn,
    var.glue_execution_role_arn,
    data.aws_caller_identity.current.arn,
  ]

  # Allow external data filtering (row/column security)
  allow_external_data_filtering = false

  # Authorised session tag value list — keep empty for standard use
  authorized_session_tag_value_list = []
}

# ── Register S3 Lakehouse Location ────────────────────────────────────────────
# Lake Formation needs to know where the data lake lives so it can enforce
# fine-grained access. The service role is used for the actual S3 calls.

resource "aws_lakeformation_resource" "lakehouse" {
  arn      = var.lakehouse_bucket_arn
  role_arn = var.lake_formation_role_arn

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# ── Database-level Permissions ────────────────────────────────────────────────

# Glue execution role — full access to all three layers (CREATE_TABLE + ALTER needed for Delta writes)
resource "aws_lakeformation_permissions" "glue_job_bronze_db" {
  principal   = var.glue_execution_role_arn
  permissions = ["ALL"]

  database {
    name = var.bronze_database_name
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_job_silver_db" {
  principal   = var.glue_execution_role_arn
  permissions = ["ALL"]

  database {
    name = var.silver_database_name
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_job_gold_db" {
  principal   = var.glue_execution_role_arn
  permissions = ["ALL"]

  database {
    name = var.gold_database_name
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# Glue crawler role — DESCRIBE + CREATE_TABLE on bronze and silver (crawlers write catalog metadata)
resource "aws_lakeformation_permissions" "glue_crawler_bronze_db" {
  principal   = var.glue_crawler_role_arn
  permissions = ["DESCRIBE", "CREATE_TABLE"]

  database {
    name = var.bronze_database_name
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_crawler_silver_db" {
  principal   = var.glue_crawler_role_arn
  permissions = ["DESCRIBE", "CREATE_TABLE"]

  database {
    name = var.silver_database_name
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# ── Table-level Permissions ───────────────────────────────────────────────────

# Glue execution role — SELECT + INSERT + DELETE + ALTER on all tables in all layers
resource "aws_lakeformation_permissions" "glue_job_bronze_tables" {
  principal   = var.glue_execution_role_arn
  permissions = ["SELECT", "INSERT", "DELETE", "ALTER", "DESCRIBE"]

  table {
    database_name = var.bronze_database_name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_job_silver_tables" {
  principal   = var.glue_execution_role_arn
  permissions = ["SELECT", "INSERT", "DELETE", "ALTER", "DESCRIBE"]

  table {
    database_name = var.silver_database_name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_job_gold_tables" {
  principal   = var.glue_execution_role_arn
  permissions = ["SELECT", "INSERT", "DELETE", "ALTER", "DESCRIBE"]

  table {
    database_name = var.gold_database_name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

# Glue crawler role — SELECT + ALTER on bronze and silver tables (updates partition metadata)
resource "aws_lakeformation_permissions" "glue_crawler_bronze_tables" {
  principal   = var.glue_crawler_role_arn
  permissions = ["SELECT", "ALTER", "DESCRIBE"]

  table {
    database_name = var.bronze_database_name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}

resource "aws_lakeformation_permissions" "glue_crawler_silver_tables" {
  principal   = var.glue_crawler_role_arn
  permissions = ["SELECT", "ALTER", "DESCRIBE"]

  table {
    database_name = var.silver_database_name
    wildcard      = true
  }

  depends_on = [aws_lakeformation_data_lake_settings.main]
}
