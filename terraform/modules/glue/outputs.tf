output "bronze_database_name" {
  description = "Glue catalog database name for the Bronze layer"
  value       = aws_glue_catalog_database.bronze.name
}

output "silver_database_name" {
  description = "Glue catalog database name for the Silver layer"
  value       = aws_glue_catalog_database.silver.name
}

output "gold_database_name" {
  description = "Glue catalog database name for the Gold layer"
  value       = aws_glue_catalog_database.gold.name
}

output "job_names" {
  description = "Map of job key to Glue job name"
  value       = { for k, job in aws_glue_job.jobs : k => job.name }
}

output "job_arns" {
  description = "Map of job key to Glue job ARN — used by Step Functions policy"
  value = {
    for k, job in aws_glue_job.jobs :
    k => "arn:aws:glue:${var.aws_region}:${var.aws_account_id}:job/${job.name}"
  }
}

output "crawler_names" {
  description = "Map of crawler key to Glue crawler name"
  value       = { for k, crawler in aws_glue_crawler.medallion : k => crawler.name }
}

output "security_configuration_name" {
  description = "Name of the Glue security configuration"
  value       = aws_glue_security_configuration.main.name
}
