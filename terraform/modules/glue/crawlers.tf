# ── Glue Crawlers ─────────────────────────────────────────────────────────────
# Six crawlers: products / orders / order_items × bronze / silver.
# Gold tables are written with known schemas by the PySpark jobs and do not need crawlers.
#
# Schema change policies:
#   Bronze  → UPDATE_IN_DATABASE  (source schema can evolve; we track it)
#   Silver  → LOG                 (schema must be explicit; alert on unexpected changes)

locals {
  domains = ["products", "orders", "order_items"]

  crawlers = {
    for pair in setproduct(local.domains, ["bronze", "silver"]) :
    "${pair[0]}_${pair[1]}" => {
      domain = pair[0]
      layer  = pair[1]
    }
  }

  # Hourly for bronze (catches new raw data quickly), daily at 07:00 UTC for silver
  crawler_schedules = {
    bronze = "cron(0 * ? * * *)"
    silver = "cron(0 7 ? * * *)"
  }

  # Bronze allows schema evolution; Silver schema is frozen after initial crawl
  schema_change_policies = {
    bronze = "UPDATE_IN_DATABASE"
    silver = "LOG"
  }
}

resource "aws_glue_crawler" "medallion" {
  for_each = local.crawlers

  name          = "${var.project_name}-${each.key}"
  role          = var.glue_crawler_role_arn
  database_name = each.value.layer == "bronze" ? aws_glue_catalog_database.bronze.name : aws_glue_catalog_database.silver.name
  description   = "Crawls ${each.value.layer}/${each.value.domain} Delta Lake tables"
  schedule      = local.crawler_schedules[each.value.layer]

  delta_target {
    delta_tables        = ["s3://${var.lakehouse_bucket_name}/${each.value.layer}/${each.value.domain}/"]
    write_manifest      = false
    create_native_delta_table = true
  }

  schema_change_policy {
    update_behavior = local.schema_change_policies[each.value.layer]
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = merge(var.tags, {
    Domain = each.value.domain
    Layer  = each.value.layer
  })

  depends_on = [
    aws_glue_catalog_database.bronze,
    aws_glue_catalog_database.silver
  ]
}
