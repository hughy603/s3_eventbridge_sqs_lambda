variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "delay_seconds" {
  description = "Seconds to delay delivery of messages"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Maximum message size in bytes"
  type        = number
  default     = 262144 # 256 KB
}

variable "message_retention_seconds" {
  description = "Number of seconds to retain a message"
  type        = number
  default     = 1209600 # 14 days
}

variable "receive_wait_time_seconds" {
  description = "Seconds to wait for long polling"
  type        = number
  default     = 20
}

variable "visibility_timeout_seconds" {
  description = "Seconds messages are hidden after delivery"
  type        = number
  default     = 300
}

variable "max_receive_count" {
  description = "Maximum number of times a message can be received before being sent to the DLQ"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "Number of seconds to retain a message in the DLQ"
  type        = number
  default     = 1209600 # 14 days
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "queue_depth_threshold" {
  description = "Threshold for queue depth alarm"
  type        = number
  default     = 100
}

variable "dlq_messages_threshold" {
  description = "Threshold for DLQ messages alarm"
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

variable "allowed_actions" {
  description = "List of SQS actions to allow"
  type        = list(string)
  default     = ["sqs:SendMessage"]
}

variable "principal_services" {
  description = "List of AWS service principals allowed to access the queue"
  type        = list(string)
  default     = ["events.amazonaws.com"]
}

variable "source_arns" {
  description = "List of source ARNs allowed to send messages to the queue"
  type        = list(string)
  default     = null
}
