variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "AWS Lambda function"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
}

variable "create_package" {
  description = "Whether to create a package from source_dir"
  type        = bool
  default     = true
}

variable "source_dir" {
  description = "Directory containing Lambda source code"
  type        = string
  default     = null
}

variable "package_file" {
  description = "Path to the Lambda deployment package"
  type        = string
  default     = null
}

variable "package_hash" {
  description = "Base64-encoded SHA256 hash of the Lambda deployment package"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "provisioned_concurrency_enabled" {
  description = "Whether to enable provisioned concurrency"
  type        = bool
  default     = false
}

variable "provisioned_concurrency" {
  description = "Number of provisioned concurrent executions"
  type        = number
  default     = 5
}

variable "auto_scaling_enabled" {
  description = "Whether to enable auto-scaling for provisioned concurrency"
  type        = bool
  default     = false
}

variable "max_concurrency" {
  description = "Maximum number of concurrent executions"
  type        = number
  default     = 100
}

variable "target_utilization" {
  description = "Target utilization for provisioned concurrency"
  type        = number
  default     = 0.7
}

variable "scale_in_cooldown" {
  description = "Scale-in cooldown period in seconds"
  type        = number
  default     = 300 # 5 minutes
}

variable "scale_out_cooldown" {
  description = "Scale-out cooldown period in seconds"
  type        = number
  default     = 30 # 30 seconds
}

variable "scale_based_on_sqs" {
  description = "Whether to scale based on SQS queue depth"
  type        = bool
  default     = false
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue for scaling"
  type        = string
  default     = null
}

variable "sqs_messages_per_function" {
  description = "Target number of SQS messages per Lambda function"
  type        = number
  default     = 10
}

variable "tracing_enabled" {
  description = "Whether to enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Lambda logs"
  type        = number
  default     = 30
}

variable "additional_policies" {
  description = "Additional IAM policy statements to attach to the Lambda role"
  type        = list(any)
  default     = []
}

variable "enable_function_dead_letter" {
  description = "Whether to enable dead-letter configuration for the function"
  type        = bool
  default     = false
}

variable "dead_letter_queue_arn" {
  description = "ARN of the SQS queue to use as dead-letter queue"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC configuration"
  type        = list(string)
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs for VPC configuration"
  type        = list(string)
  default     = null
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "error_threshold" {
  description = "Threshold for Lambda errors alarm"
  type        = number
  default     = 1
}

variable "throttle_threshold" {
  description = "Threshold for Lambda throttles alarm"
  type        = number
  default     = 1
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs to notify when alarm resolves"
  type        = list(string)
  default     = []
}
