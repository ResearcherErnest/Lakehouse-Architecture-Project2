variable "project_name" {
  description = "Short project identifier — used as prefix for all resource names"
  type        = string
  default     = "ecom-lakehouse"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID — used to make S3 bucket names globally unique"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs for private subnets (min 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — must match length of availability_zones"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "glue_worker_type" {
  description = "Glue worker type — G.1X for dev/lab, G.2X for production"
  type        = string
  default     = "G.1X"
}

variable "glue_num_workers" {
  description = "Number of Glue workers per ETL job"
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "monthly_budget_usd" {
  description = "Monthly AWS spend budget in USD"
  type        = number
  default     = 500
}

variable "sns_alert_email" {
  description = "Email address for pipeline failure and budget alerts (optional)"
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "EventBridge cron expression for daily pipeline trigger (UTC)"
  type        = string
  default     = "cron(0 6 * * ? *)"
}
