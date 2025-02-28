output "bucket_id" {
  description = "The ID of the S3 bucket"
  value       = var.create_bucket ? module.s3_bucket[0].bucket_id : var.existing_bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = var.create_bucket ? module.s3_bucket[0].bucket_arn : var.existing_bucket_arn
}

output "queue_url" {
  description = "The URL of the SQS queue"
  value       = module.object_queue.queue_url
}

output "queue_arn" {
  description = "The ARN of the SQS queue"
  value       = module.object_queue.queue_arn
}

output "queue_name" {
  description = "The name of the SQS queue"
  value       = module.object_queue.queue_name
}

output "dlq_url" {
  description = "The URL of the DLQ for failed messages"
  value       = module.object_queue.dlq_url
}

output "dlq_arn" {
  description = "The ARN of the DLQ for failed messages"
  value       = module.object_queue.dlq_arn
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = module.lambda_function.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = module.lambda_function.function_arn
}

output "lambda_dlq_url" {
  description = "The URL of the Lambda DLQ"
  value       = module.lambda_dlq.queue_url
}

output "lambda_dlq_arn" {
  description = "The ARN of the Lambda DLQ"
  value       = module.lambda_dlq.queue_arn
}

output "event_rule_id" {
  description = "The ID of the EventBridge rule"
  value       = module.eventbridge_rule.event_rule_id
}

output "event_rule_arn" {
  description = "The ARN of the EventBridge rule"
  value       = module.eventbridge_rule.event_rule_arn
}

output "state_machine_id" {
  description = "The ID of the Step Functions state machine"
  value       = module.step_functions.state_machine_id
}

output "state_machine_arn" {
  description = "The ARN of the Step Functions state machine"
  value       = module.step_functions.state_machine_arn
}

output "step_functions_dlq_url" {
  description = "The URL of the Step Functions DLQ"
  value       = module.step_functions.dlq_url
}

output "step_functions_dlq_arn" {
  description = "The ARN of the Step Functions DLQ"
  value       = module.step_functions.dlq_arn
}
