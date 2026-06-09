output "raw_bucket_name" {
  description = "Upload source files here to trigger the pipeline"
  value       = module.storage.raw_bucket_name
}

output "lakehouse_bucket_name" {
  description = "S3 bucket containing bronze/silver/gold Delta Lake tables"
  value       = module.storage.lakehouse_bucket_name
}

output "glue_assets_bucket_name" {
  description = "Upload PySpark scripts here before running the pipeline"
  value       = module.storage.glue_assets_bucket_name
}

output "state_machine_arn" {
  description = "Step Functions ARN — use this to manually trigger a pipeline run"
  value       = module.step_functions.state_machine_arn
}

output "athena_primary_workgroup" {
  description = "Athena workgroup for analyst Gold layer queries"
  value       = module.athena.primary_workgroup_name
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name for pipeline observability"
  value       = module.monitoring.dashboard_name
}

output "kms_key_alias" {
  description = "KMS key alias used for all encryption"
  value       = module.kms.key_alias
}

output "glue_job_names" {
  description = "Map of job key to Glue job name"
  value       = module.glue.job_names
}
