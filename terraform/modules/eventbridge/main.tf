# ── IAM Role for EventBridge to invoke Step Functions ─────────────────────────

resource "aws_iam_role" "eventbridge" {
  name        = "${var.project_name}-eventbridge"
  description = "Allows EventBridge rules to start the lakehouse pipeline state machine"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
          "aws:SourceRegion"  = var.aws_region
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "${var.project_name}-eventbridge-sfn"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [var.state_machine_arn]
    }]
  })
}

# ── Daily Scheduled Trigger ───────────────────────────────────────────────────
# Fires every day at 06:00 UTC and passes today's date as execution_date.

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "${var.project_name}-daily-pipeline"
  description         = "Triggers the lakehouse pipeline daily at 06:00 UTC"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "daily_schedule" {
  rule     = aws_cloudwatch_event_rule.daily_schedule.name
  arn      = var.state_machine_arn
  role_arn = aws_iam_role.eventbridge.arn

  # Derive execution_date from the scheduled event time
  input_transformer {
    input_paths = {
      time = "$.time"
    }
    input_template = "{\"execution_date\": \"<time>\"}"
  }
}

# ── S3 Event-Driven Trigger ───────────────────────────────────────────────────
# Fires when new objects land in the raw bucket uploads/ prefix.
# Requires EventBridge notifications enabled on the bucket (done in storage module).

resource "aws_cloudwatch_event_rule" "s3_upload" {
  name        = "${var.project_name}-s3-upload-trigger"
  description = "Triggers the lakehouse pipeline when new files land in the raw bucket"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [var.raw_bucket_name] }
      object = { key = [{ prefix = "uploads/" }] }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "s3_upload" {
  rule     = aws_cloudwatch_event_rule.s3_upload.name
  arn      = var.state_machine_arn
  role_arn = aws_iam_role.eventbridge.arn

  # Pass the S3 object key and event time to the pipeline
  input_transformer {
    input_paths = {
      time       = "$.time"
      bucket     = "$.detail.bucket.name"
      object_key = "$.detail.object.key"
    }
    input_template = "{\"execution_date\": \"<time>\", \"source_bucket\": \"<bucket>\", \"source_key\": \"<object_key>\"}"
  }
}
