# ── SNS Alert Topic ───────────────────────────────────────────────────────────

resource "aws_sns_topic" "pipeline_alerts" {
  name              = "${var.project_name}-pipeline-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.sns_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_alert_email
}

# ── CloudWatch Log Group for SF execution history ─────────────────────────────

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${var.project_name}-pipeline"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

# ── State Machine ─────────────────────────────────────────────────────────────

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-pipeline"
  role_arn = var.step_functions_role_arn
  type     = "EXPRESS"

  definition = templatefile("${path.module}/state_machine.json.tpl", {
    raw_to_bronze_job          = var.glue_job_names["raw_to_bronze"]
    products_silver_job        = var.glue_job_names["products_silver"]
    orders_silver_job          = var.glue_job_names["orders_silver"]
    order_items_silver_job     = var.glue_job_names["order_items_silver"]
    daily_revenue_gold_job     = var.glue_job_names["daily_revenue_gold"]
    product_performance_gold_job = var.glue_job_names["product_performance_gold"]
    customer_orders_gold_job   = var.glue_job_names["customer_orders_gold"]

    products_bronze_crawler    = var.glue_crawler_names["products_bronze"]
    orders_bronze_crawler      = var.glue_crawler_names["orders_bronze"]
    order_items_bronze_crawler = var.glue_crawler_names["order_items_bronze"]

    sns_topic_arn              = aws_sns_topic.pipeline_alerts.arn
    aws_region                 = var.aws_region
    aws_account_id             = var.aws_account_id
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = var.tags
}
