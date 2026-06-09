variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "glue_execution_role_arn" {
  description = "ARN of the Glue ETL job execution role"
  type        = string
}

variable "glue_crawler_role_arn" {
  description = "ARN of the Glue crawler role"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Name of the lakehouse S3 bucket"
  type        = string
}

variable "glue_assets_bucket_name" {
  description = "Name of the Glue assets bucket (scripts, temp files)"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw landing S3 bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the CMK for Glue job encryption"
  type        = string
}

variable "vpc_subnet_ids" {
  description = "Private subnet IDs for the Glue VPC connection"
  type        = list(string)
}

variable "glue_security_group_id" {
  description = "Security group ID for Glue jobs"
  type        = string
}

variable "worker_type" {
  description = "Glue worker type — G.1X for dev, G.2X for prod"
  type        = string
  default     = "G.1X"

  validation {
    condition     = contains(["G.025X", "G.1X", "G.2X", "G.4X", "G.8X"], var.worker_type)
    error_message = "worker_type must be a valid Glue worker type."
  }
}

variable "num_workers" {
  description = "Number of Glue workers per job"
  type        = number
  default     = 2
}

variable "job_timeout_minutes" {
  description = "Maximum runtime for each Glue job before it is forcibly stopped"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
