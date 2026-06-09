# ── Glue Data Catalog Databases ───────────────────────────────────────────────
# Three databases for the medallion layers. Location URIs point to their
# respective S3 prefixes so crawlers and LF can register them correctly.

resource "aws_glue_catalog_database" "bronze" {
  name        = "${var.project_name}_bronze"
  description = "Raw replica of source data — no transformations applied"

  location_uri = "s3://${var.lakehouse_bucket_name}/bronze/"

  tags = var.tags
}

resource "aws_glue_catalog_database" "silver" {
  name        = "${var.project_name}_silver"
  description = "Cleansed, typed, deduplicated data with SCD2 for slowly-changing dimensions"

  location_uri = "s3://${var.lakehouse_bucket_name}/silver/"

  tags = var.tags
}

resource "aws_glue_catalog_database" "gold" {
  name        = "${var.project_name}_gold"
  description = "Aggregated, analytics-ready business assets"

  location_uri = "s3://${var.lakehouse_bucket_name}/gold/"

  tags = var.tags
}
