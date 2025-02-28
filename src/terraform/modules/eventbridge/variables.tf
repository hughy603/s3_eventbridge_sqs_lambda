variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "bucket_id" {
  description = "ID of the S3 bucket to monitor for events"
  type        = string
}

variable "queue_arn" {
  description = "ARN of the SQS queue to send events to"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_content_filtering" {
  description = "Enable content-based filtering rules"
  type        = bool
  default     = true
}

variable "priority_queue_arn" {
  description = "ARN of the SQS queue for high priority events"
  type        = string
  default     = null
}

variable "large_file_queue_arn" {
  description = "ARN of the SQS queue for large file events"
  type        = string
  default     = null
}

variable "key_prefix" {
  description = "Optional prefix to filter object keys"
  type        = string
  default     = null
}

variable "min_size_bytes" {
  description = "Minimum object size in bytes to process"
  type        = number
  default     = null
}
