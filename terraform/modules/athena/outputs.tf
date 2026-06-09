output "primary_workgroup_name" {
  description = "Name of the primary Athena workgroup (analysts)"
  value       = aws_athena_workgroup.primary.name
}

output "engineering_workgroup_name" {
  description = "Name of the engineering Athena workgroup (data engineers)"
  value       = aws_athena_workgroup.engineering.name
}
