output "bucket_id" {
  description = "The ID of the S3 bucket"
  value       = module.process_objects.bucket_id
}

output "queue_url" {
  description = "The URL of the SQS queue"
  value       = module.process_objects.queue_url
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = module.process_objects.lambda_function_name
}

output "state_machine_arn" {
  description = "The ARN of the Step Functions state machine"
  value       = module.process_objects.state_machine_arn
}
