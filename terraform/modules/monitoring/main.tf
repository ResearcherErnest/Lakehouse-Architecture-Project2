# ── CloudWatch Log Groups for Glue jobs ───────────────────────────────────────

resource "aws_cloudwatch_log_group" "glue_jobs" {
  name              = "/aws-glue/jobs/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "glue_crawlers" {
  name              = "/aws-glue/crawlers/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# Alarm: any Glue job failure
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  for_each = var.glue_job_names

  alarm_name          = "${var.project_name}-glue-${each.value}-failure"
  alarm_description   = "Glue job ${each.value} has failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTask"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = each.value
    Type    = "gauge"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = var.tags
}

# Alarm: Step Functions pipeline SLA breach
resource "aws_cloudwatch_metric_alarm" "pipeline_sla" {
  alarm_name          = "${var.project_name}-pipeline-sla-breach"
  alarm_description   = "Pipeline execution exceeded ${var.pipeline_sla_minutes} minute SLA"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionTime"
  namespace           = "AWS/States"
  period              = 60
  extended_statistic  = "p99"
  threshold           = var.pipeline_sla_minutes * 60 * 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}"
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

# Alarm: Step Functions execution failures
resource "aws_cloudwatch_metric_alarm" "pipeline_failures" {
  alarm_name          = "${var.project_name}-pipeline-execution-failed"
  alarm_description   = "One or more lakehouse pipeline executions have failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}"
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "lakehouse" {
  dashboard_name = "${var.project_name}-lakehouse"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Pipeline Executions (7d)"
          view   = "timeSeries"
          region = var.aws_region
          period = 86400
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}", { label = "Started" }],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}", { label = "Succeeded" }],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}", { label = "Failed" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Pipeline Execution Duration p99 (ms)"
          view   = "timeSeries"
          region = var.aws_region
          period = 86400
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", "arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:${var.state_machine_name}", { stat = "p99", label = "p99 Duration" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title   = "Lakehouse S3 Storage (bytes)"
          view    = "timeSeries"
          region  = var.aws_region
          period  = 86400
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.lakehouse_bucket_name, "StorageType", "StandardStorage", { label = "Total Lakehouse" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Athena Data Scanned (bytes)"
          view   = "timeSeries"
          region = var.aws_region
          period = 86400
          metrics = [
            ["AWS/Athena", "DataScannedInBytes", "WorkGroup", "${var.project_name}-primary", { label = "Primary WG", stat = "Sum" }],
            ["AWS/Athena", "DataScannedInBytes", "WorkGroup", "${var.project_name}-engineering", { label = "Engineering WG", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Athena Query Count"
          view   = "timeSeries"
          region = var.aws_region
          period = 86400
          metrics = [
            ["AWS/Athena", "TotalExecutionTime", "WorkGroup", "${var.project_name}-primary", { stat = "SampleCount", label = "Primary queries" }],
            ["AWS/Athena", "TotalExecutionTime", "WorkGroup", "${var.project_name}-engineering", { stat = "SampleCount", label = "Engineering queries" }]
          ]
        }
      }
    ]
  })
}

# ── AWS Budgets ───────────────────────────────────────────────────────────────

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_email != "" ? [var.budget_alert_email] : []
    subscriber_sns_topic_arns  = [var.sns_topic_arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_email != "" ? [var.budget_alert_email] : []
    subscriber_sns_topic_arns  = [var.sns_topic_arn]
  }
}
