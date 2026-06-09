output "key_arn" {
  description = "ARN of the CMK — pass to S3 SSE-KMS, Glue, and CloudWatch Logs resources"
  value       = aws_kms_key.main.arn
}

output "key_id" {
  description = "Key ID of the CMK"
  value       = aws_kms_key.main.key_id
}

output "key_alias" {
  description = "Alias name of the CMK (e.g. alias/ecom-lakehouse)"
  value       = aws_kms_alias.main.name
}
