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

variable "glue_job_names" {
  description = "Map of job key to Glue job name"
  type        = map(string)
}

variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS alerts topic (from step_functions module)"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Name of the lakehouse S3 bucket"
  type        = string
}

variable "pipeline_sla_minutes" {
  description = "Maximum acceptable pipeline runtime in minutes before SLA breach alarm fires"
  type        = number
  default     = 180
}

variable "monthly_budget_usd" {
  description = "Monthly AWS spend budget in USD — alerts at 80% and 100%"
  type        = number
  default     = 500
}

variable "budget_alert_email" {
  description = "Email address for AWS Budgets cost alerts"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Glue job logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
