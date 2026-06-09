output "raw_bucket_name" {
  description = "Name of the raw landing S3 bucket"
  value       = aws_s3_bucket.buckets["raw"].bucket
}

output "raw_bucket_arn" {
  description = "ARN of the raw landing S3 bucket"
  value       = aws_s3_bucket.buckets["raw"].arn
}

output "lakehouse_bucket_name" {
  description = "Name of the lakehouse S3 bucket (holds bronze/silver/gold prefixes)"
  value       = aws_s3_bucket.buckets["lakehouse"].bucket
}

output "lakehouse_bucket_arn" {
  description = "ARN of the lakehouse S3 bucket"
  value       = aws_s3_bucket.buckets["lakehouse"].arn
}

output "glue_assets_bucket_name" {
  description = "Name of the Glue assets bucket (PySpark scripts, temp files)"
  value       = aws_s3_bucket.buckets["glue_assets"].bucket
}

output "glue_assets_bucket_arn" {
  description = "ARN of the Glue assets bucket"
  value       = aws_s3_bucket.buckets["glue_assets"].arn
}

output "athena_results_bucket_name" {
  description = "Name of the Athena query results bucket"
  value       = aws_s3_bucket.buckets["athena_results"].bucket
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query results bucket"
  value       = aws_s3_bucket.buckets["athena_results"].arn
}

output "bucket_arns" {
  description = "Map of purpose → bucket ARN for use in IAM policies"
  value = {
    for k, _ in local.buckets : k => aws_s3_bucket.buckets[k].arn
  }
}
