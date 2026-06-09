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

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to trigger"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw landing S3 bucket — S3 events originate here"
  type        = string
}

variable "schedule_expression" {
  description = "Cron or rate expression for the daily scheduled trigger (UTC)"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
