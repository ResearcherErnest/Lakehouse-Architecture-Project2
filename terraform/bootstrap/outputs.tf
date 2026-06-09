output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state — use this in backend.tf"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_lock_table_name" {
  description = "DynamoDB table name for state locking — use this in backend.tf"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config_snippet" {
  description = "Paste this into terraform/backend.tf after bootstrap apply"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "ecom-lakehouse/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
        encrypt        = true
      }
    }
  EOT
}
