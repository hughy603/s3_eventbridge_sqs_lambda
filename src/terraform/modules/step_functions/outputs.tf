output "state_machine_id" {
  description = "ID of the Step Functions state machine"
  value       = aws_sfn_state_machine.this.id
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_id" {
  description = "ID of the Step Functions IAM role"
  value       = aws_iam_role.step_functions.id
}

output "role_arn" {
  description = "ARN of the Step Functions IAM role"
  value       = aws_iam_role.step_functions.arn
}

output "role_name" {
  description = "Name of the Step Functions IAM role"
  value       = aws_iam_role.step_functions.name
}

output "dlq_id" {
  description = "ID of the Step Functions DLQ"
  value       = aws_sqs_queue.step_functions_dlq.id
}

output "dlq_arn" {
  description = "ARN of the Step Functions DLQ"
  value       = aws_sqs_queue.step_functions_dlq.arn
}

output "dlq_url" {
  description = "URL of the Step Functions DLQ"
  value       = aws_sqs_queue.step_functions_dlq.url
}
