output "glue_execution_role_arn" {
  description = "ARN of the Glue ETL job execution role"
  value       = aws_iam_role.glue_execution.arn
}

output "glue_execution_role_name" {
  description = "Name of the Glue ETL job execution role"
  value       = aws_iam_role.glue_execution.name
}

output "glue_crawler_role_arn" {
  description = "ARN of the Glue crawler role"
  value       = aws_iam_role.glue_crawler.arn
}

output "glue_crawler_role_name" {
  description = "Name of the Glue crawler role"
  value       = aws_iam_role.glue_crawler.name
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions.arn
}

output "lake_formation_role_arn" {
  description = "ARN of the Lake Formation service role"
  value       = aws_iam_role.lake_formation.arn
}
