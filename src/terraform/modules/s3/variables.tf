variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_versioning" {
  description = "Enable bucket versioning"
  type        = bool
  default     = true
}

variable "access_log_bucket_name" {
  description = "Name of the bucket to store access logs. If null, access logging is disabled."
  type        = string
  default     = null
}

variable "enable_lifecycle_rules" {
  description = "Enable lifecycle rules for the bucket"
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to retain noncurrent versions before deletion"
  type        = number
  default     = 90
}
