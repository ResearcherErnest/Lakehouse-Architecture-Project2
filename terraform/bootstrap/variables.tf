variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
  default     = "ecom-lakehouse"
}

variable "aws_region" {
  description = "AWS region for all bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID — used to make bucket names globally unique"
  type        = string
}
