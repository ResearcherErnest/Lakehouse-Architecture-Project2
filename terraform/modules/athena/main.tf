# ── Primary Workgroup (analysts querying Gold layer) ──────────────────────────

resource "aws_athena_workgroup" "primary" {
  name        = "${var.project_name}-primary"
  description = "Default workgroup for analysts querying the Gold layer"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    # Fail queries that would scan more than the cutoff — prevents runaway cost
    bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${var.athena_results_bucket_name}/primary/"
      # Results bucket has SSE-KMS applied at bucket level — no workgroup override needed
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.tags
}

# ── Engineering Workgroup (data engineers querying all layers) ────────────────

resource "aws_athena_workgroup" "engineering" {
  name        = "${var.project_name}-engineering"
  description = "Workgroup for data engineers - access to bronze, silver, and gold layers"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    # Higher limit for engineering debugging queries
    bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff * 5

    result_configuration {
      output_location = "s3://${var.athena_results_bucket_name}/engineering/"
      # Results bucket has SSE-KMS applied at bucket level — no workgroup override needed
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.tags
}

# ── Named Queries (Gold layer analytical patterns) ────────────────────────────

resource "aws_athena_named_query" "daily_revenue_by_dept" {
  name        = "${var.project_name}-daily-revenue-by-department"
  workgroup   = aws_athena_workgroup.primary.name
  database    = var.gold_database_name
  description = "Total daily revenue grouped by department for the last 30 days"

  query = <<-SQL
    SELECT
      order_date,
      department,
      order_count,
      unique_customers,
      gross_revenue,
      net_revenue
    FROM "${var.gold_database_name}"."daily_revenue"
    WHERE order_date >= DATE_ADD('day', -30, CURRENT_DATE)
    ORDER BY order_date DESC, net_revenue DESC;
  SQL
}

resource "aws_athena_named_query" "top_products_by_dept" {
  name        = "${var.project_name}-top-products-by-department"
  workgroup   = aws_athena_workgroup.primary.name
  database    = var.gold_database_name
  description = "Top 10 products by revenue per department for the current month"

  query = <<-SQL
    SELECT
      department,
      product_name,
      units_sold,
      revenue,
      avg_selling_price,
      dept_revenue_rank
    FROM "${var.gold_database_name}"."product_performance"
    WHERE order_month = DATE_TRUNC('month', CURRENT_DATE)
      AND dept_revenue_rank <= 10
    ORDER BY department, dept_revenue_rank;
  SQL
}

resource "aws_athena_named_query" "customer_lifetime_value" {
  name        = "${var.project_name}-customer-lifetime-value"
  workgroup   = aws_athena_workgroup.primary.name
  database    = var.gold_database_name
  description = "Customer lifetime value distribution - top 100 by lifetime value"

  query = <<-SQL
    SELECT
      customer_id,
      lifetime_orders,
      lifetime_value,
      avg_order_value,
      avg_days_between_orders,
      first_order_date,
      last_order_date
    FROM "${var.gold_database_name}"."customer_orders"
    ORDER BY lifetime_value DESC
    LIMIT 100;
  SQL
}

resource "aws_athena_named_query" "silver_data_quality_check" {
  name        = "${var.project_name}-silver-data-quality-check"
  workgroup   = aws_athena_workgroup.engineering.name
  database    = var.silver_database_name
  description = "Quick data quality check on Silver orders - null counts and date range"

  query = <<-SQL
    SELECT
      COUNT(*)                                                AS total_rows,
      COUNT(DISTINCT order_id)                               AS unique_orders,
      SUM(CASE WHEN order_id   IS NULL THEN 1 ELSE 0 END)   AS null_order_ids,
      SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END)   AS null_user_ids,
      SUM(CASE WHEN total_amount <= 0  THEN 1 ELSE 0 END)   AS invalid_amounts,
      MIN(order_date)                                        AS earliest_order,
      MAX(order_date)                                        AS latest_order
    FROM "${var.silver_database_name}"."orders";
  SQL
}
