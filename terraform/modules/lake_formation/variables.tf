variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "lakehouse_bucket_arn" {
  description = "ARN of the lakehouse S3 bucket to register as a Lake Formation location"
  type        = string
}

variable "lake_formation_role_arn" {
  description = "ARN of the IAM role Lake Formation uses to access the S3 location"
  type        = string
}

variable "glue_execution_role_arn" {
  description = "ARN of the Glue ETL job role — granted read/write on all three layers"
  type        = string
}

variable "glue_crawler_role_arn" {
  description = "ARN of the Glue crawler role — granted read on bronze and silver"
  type        = string
}

variable "bronze_database_name" {
  description = "Glue catalog database name for the Bronze layer"
  type        = string
}

variable "silver_database_name" {
  description = "Glue catalog database name for the Silver layer"
  type        = string
}

variable "gold_database_name" {
  description = "Glue catalog database name for the Gold layer"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
