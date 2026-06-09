output "state_machine_arn" {
  description = "ARN of the Step Functions state machine — used by EventBridge as trigger target"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.pipeline.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS pipeline alerts topic"
  value       = aws_sns_topic.pipeline_alerts.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name for Step Functions execution history"
  value       = aws_cloudwatch_log_group.step_functions.name
}
