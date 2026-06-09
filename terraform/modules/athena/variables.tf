variable "project_name" {
  description = "Short project identifier used in all resource names"
  type        = string
}

variable "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena query results"
  type        = string
}

variable "gold_database_name" {
  description = "Glue catalog database name for the Gold layer"
  type        = string
}

variable "silver_database_name" {
  description = "Glue catalog database name for the Silver layer"
  type        = string
}

variable "bytes_scanned_cutoff" {
  description = "Per-query data scanned limit in bytes (cost guardrail). Default 1 GB."
  type        = number
  default     = 1073741824
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
