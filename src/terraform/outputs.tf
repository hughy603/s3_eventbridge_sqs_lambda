output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.s3_bucket.bucket_id
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = module.object_queue.queue_url
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.process_object_lambda.function_name
}

output "step_functions_arn" {
  description = "ARN of the Step Functions state machine"
  value       = module.step_functions.state_machine_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = module.eventbridge_rule.event_rule_name
}

output "lambda_dlq_url" {
  description = "URL of the Lambda DLQ"
  value       = module.lambda_dlq.queue_url
}

output "step_functions_dlq_url" {
  description = "URL of the Step Functions DLQ"
  value       = module.step_functions.dlq_url
}
