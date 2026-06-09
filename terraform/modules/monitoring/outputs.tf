output "dashboard_name" {
  description = "Name of the CloudWatch lakehouse dashboard"
  value       = aws_cloudwatch_dashboard.lakehouse.dashboard_name
}

output "glue_log_group_name" {
  description = "CloudWatch Log Group name for Glue job logs"
  value       = aws_cloudwatch_log_group.glue_jobs.name
}
