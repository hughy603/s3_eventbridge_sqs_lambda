variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "definition" {
  description = "JSON definition of the state machine"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = "IAM policy statements for the Step Functions role"
  type        = list(any)
}

variable "log_retention_days" {
  description = "Number of days to retain Step Functions logs"
  type        = number
  default     = 30
}

variable "dlq_message_retention_seconds" {
  description = "Number of seconds to retain a message in the DLQ"
  type        = number
  default     = 1209600 # 14 days
}

variable "enable_scheduled_execution" {
  description = "Whether to enable scheduled execution of the state machine"
  type        = bool
  default     = false
}

variable "schedule_expression" {
  description = "Schedule expression for state machine execution"
  type        = string
  default     = "rate(1 minute)"
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "failure_threshold" {
  description = "Threshold for Step Functions failures alarm"
  type        = number
  default     = 1
}

variable "timeout_threshold" {
  description = "Threshold for Step Functions timeouts alarm"
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

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard"
  type        = bool
  default     = true
}
