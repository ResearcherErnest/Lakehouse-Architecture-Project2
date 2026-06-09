output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "glue_security_group_id" {
  description = "Security group ID to attach to Glue connections and jobs"
  value       = aws_security_group.glue.id
}

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}
