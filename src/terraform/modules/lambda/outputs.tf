output "function_id" {
  description = "ID of the Lambda function"
  value       = aws_lambda_function.this.id
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "alias_arn" {
  description = "ARN of the Lambda alias"
  value       = aws_lambda_alias.this.arn
}

output "alias_name" {
  description = "Name of the Lambda alias"
  value       = aws_lambda_alias.this.name
}

output "role_id" {
  description = "ID of the Lambda IAM role"
  value       = aws_iam_role.lambda.id
}

output "role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "role_name" {
  description = "Name of the Lambda IAM role"
  value       = aws_iam_role.lambda.name
}

output "log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "log_group_arn" {
  description = "ARN of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.arn
}
