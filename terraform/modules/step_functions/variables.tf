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

variable "step_functions_role_arn" {
  description = "ARN of the IAM role assumed by the state machine"
  type        = string
}

variable "glue_job_names" {
  description = "Map of job key to Glue job name (from glue module outputs)"
  type        = map(string)
}

variable "glue_crawler_names" {
  description = "Map of crawler key to Glue crawler name (from glue module outputs)"
  type        = map(string)
}

variable "sns_alert_email" {
  description = "Email address to receive pipeline failure alerts"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "ARN of the CMK for encrypting execution logs"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
