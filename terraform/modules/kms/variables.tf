variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used in key policy to grant root admin access"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used to scope key policy conditions"
  type        = string
}

variable "deletion_window_days" {
  description = "Waiting period (7–30 days) before a scheduled key deletion takes effect"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_days >= 7 && var.deletion_window_days <= 30
    error_message = "deletion_window_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
