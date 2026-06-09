output "daily_rule_arn" {
  description = "ARN of the daily scheduled EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_schedule.arn
}

output "s3_upload_rule_arn" {
  description = "ARN of the S3-event-driven EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_upload.arn
}

output "eventbridge_role_arn" {
  description = "ARN of the IAM role used by EventBridge to start the state machine"
  value       = aws_iam_role.eventbridge.arn
}
