output "lakehouse_location_arn" {
  description = "ARN of the registered Lake Formation S3 data lake location"
  value       = aws_lakeformation_resource.lakehouse.arn
}
