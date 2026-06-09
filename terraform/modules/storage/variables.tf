variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — appended to bucket names for global uniqueness"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in EventBridge notification config"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the CMK used for SSE-KMS on all lakehouse buckets"
  type        = string
}

variable "raw_retention_days" {
  description = "Days before raw landing objects transition to S3-IA"
  type        = number
  default     = 30
}

variable "raw_glacier_days" {
  description = "Days before raw landing objects transition to Glacier"
  type        = number
  default     = 90
}

variable "athena_results_expiry_days" {
  description = "Days before Athena query result objects are expired"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
