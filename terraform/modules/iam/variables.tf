variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used in policy conditions"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in RequestedRegion policy conditions"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the CMK — granted to Glue and crawler roles for SSE-KMS operations"
  type        = string
}

variable "lakehouse_bucket_arn" {
  description = "ARN of the lakehouse S3 bucket (bronze/silver/gold)"
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw landing S3 bucket"
  type        = string
}

variable "glue_assets_bucket_arn" {
  description = "ARN of the Glue assets bucket (scripts, temp files)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
