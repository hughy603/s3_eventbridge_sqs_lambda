output "queue_id" {
  description = "ID of the SQS queue"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.main.url
}

output "queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.main.name
}

output "dlq_id" {
  description = "ID of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.name
}
