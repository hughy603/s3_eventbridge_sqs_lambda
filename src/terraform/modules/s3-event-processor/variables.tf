variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# S3 Bucket Variables
variable "create_bucket" {
  description = "Whether to create a new S3 bucket or use an existing one"
  type        = bool
  default     = true
}

variable "existing_bucket_id" {
  description = "ID of an existing S3 bucket to use if create_bucket is false"
  type        = string
  default     = null
}

variable "existing_bucket_arn" {
  description = "ARN of an existing S3 bucket to use if create_bucket is false"
  type        = string
  default     = null
}

variable "s3_enable_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_access_log_bucket_name" {
  description = "Name of the bucket to use for access logs"
  type        = string
  default     = null
}

variable "s3_enable_lifecycle_rules" {
  description = "Enable lifecycle rules for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_noncurrent_version_expiration_days" {
  description = "Number of days to retain noncurrent versions (if lifecycle rules are enabled)"
  type        = number
  default     = 30
}

# SQS Variables
variable "sqs_queue_name" {
  description = "Name of the SQS queue"
  type        = string
  default     = "object-queue"
}

variable "sqs_delay_seconds" {
  description = "Delay seconds for SQS queue"
  type        = number
  default     = 0
}

variable "sqs_max_message_size" {
  description = "Maximum message size in bytes for SQS queue"
  type        = number
  default     = 262144
}

variable "sqs_message_retention_seconds" {
  description = "Message retention period in seconds for SQS queue"
  type        = number
  default     = 1209600 # 14 days
}

variable "sqs_receive_wait_time_seconds" {
  description = "Receive wait time in seconds for SQS queue (long polling)"
  type        = number
  default     = 20
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout in seconds for SQS queue"
  type        = number
  default     = 300
}

variable "sqs_max_receive_count" {
  description = "Maximum number of receives before a message is sent to the DLQ"
  type        = number
  default     = 3
}

variable "sqs_queue_depth_threshold" {
  description = "Threshold for SQS queue depth alarm"
  type        = number
  default     = 100
}

variable "sqs_dlq_messages_threshold" {
  description = "Threshold for SQS DLQ messages alarm"
  type        = number
  default     = 1
}

# Lambda Variables
variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "Process objects from S3"
}

variable "lambda_handler" {
  description = "Handler for the Lambda function"
  type        = string
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for the Lambda function"
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Memory size in MB for the Lambda function"
  type        = number
  default     = 512
}

variable "lambda_create_package" {
  description = "Whether to create a Lambda deployment package"
  type        = bool
  default     = true
}

variable "lambda_source_dir" {
  description = "Directory containing Lambda source code"
  type        = string
  default     = null
}

variable "lambda_filename" {
  description = "Path to the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_s3_key" {
  description = "S3 key for the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = { LOG_LEVEL = "INFO" }
}

variable "lambda_provisioned_concurrency_enabled" {
  description = "Whether to enable provisioned concurrency for the Lambda function"
  type        = bool
  default     = false
}

variable "lambda_provisioned_concurrency" {
  description = "Number of provisioned concurrent executions for the Lambda function"
  type        = number
  default     = 5
}

variable "lambda_auto_scaling_enabled" {
  description = "Whether to enable auto-scaling for the Lambda function"
  type        = bool
  default     = true
}

variable "lambda_max_concurrency" {
  description = "Maximum concurrency for the Lambda function"
  type        = number
  default     = 100
}

variable "lambda_target_utilization" {
  description = "Target utilization for Lambda auto-scaling"
  type        = number
  default     = 0.7
}

variable "lambda_scale_in_cooldown" {
  description = "Scale-in cooldown period in seconds for Lambda auto-scaling"
  type        = number
  default     = 300
}

variable "lambda_scale_out_cooldown" {
  description = "Scale-out cooldown period in seconds for Lambda auto-scaling"
  type        = number
  default     = 30
}

variable "lambda_scale_based_on_sqs" {
  description = "Whether to scale Lambda based on SQS queue depth"
  type        = bool
  default     = true
}

variable "lambda_sqs_messages_per_function" {
  description = "Target number of SQS messages per Lambda function instance"
  type        = number
  default     = 10
}

variable "lambda_additional_policies" {
  description = "Additional IAM policies for the Lambda function"
  type        = list(map(any))
  default     = []
}

variable "lambda_enable_function_dead_letter" {
  description = "Whether to enable a DLQ for the Lambda function"
  type        = bool
  default     = true
}

variable "lambda_tracing_enabled" {
  description = "Whether to enable X-Ray tracing for the Lambda function"
  type        = bool
  default     = true
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 1
}

variable "lambda_throttle_threshold" {
  description = "Threshold for Lambda throttle alarm"
  type        = number
  default     = 1
}

# Step Functions Variables
variable "step_functions_name" {
  description = "Name of the Step Functions state machine"
  type        = string
  default     = "process-objects"
}

variable "step_functions_max_concurrency" {
  description = "Maximum concurrency for the Map state in Step Functions"
  type        = number
  default     = 3
}

variable "step_functions_enable_scheduled_execution" {
  description = "Whether to enable scheduled execution of the Step Functions state machine"
  type        = bool
  default     = true
}

variable "step_functions_schedule_expression" {
  description = "Schedule expression for the Step Functions state machine"
  type        = string
  default     = "rate(1 minute)"
}

variable "step_functions_failure_threshold" {
  description = "Threshold for Step Functions failure alarm"
  type        = number
  default     = 1
}

variable "step_functions_timeout_threshold" {
  description = "Threshold for Step Functions timeout alarm"
  type        = number
  default     = 1
}

# Monitoring Variables
variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to trigger when alarms are activated"
  type        = list(string)
  default     = []
}

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard"
  type        = bool
  default     = false # Disabled by default since we're using Dynatrace
}

# Dynatrace Integration Variables
variable "enable_dynatrace_integration" {
  description = "Whether to enable Dynatrace integration for metric monitoring"
  type        = bool
  default     = true
}

variable "generate_dynatrace_dashboard" {
  description = "Whether to generate a Dynatrace dashboard JSON file"
  type        = bool
  default     = true
}

variable "dynatrace_sync_lambda_arn" {
  description = "ARN of the Lambda function used to sync metrics with Dynatrace"
  type        = string
  default     = null
}

# Splunk Integration Variables
variable "enable_splunk_integration" {
  description = "Whether to enable Splunk integration for log analytics"
  type        = bool
  default     = true
}

variable "splunk_forwarder_lambda_arn" {
  description = "ARN of the Lambda function used to forward logs to Splunk"
  type        = string
  default     = null
}

variable "splunk_index_name" {
  description = "Name of the Splunk index for logs"
  type        = string
  default     = "aws_lambda"
}
