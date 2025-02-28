# Auto-scaling for Lambda concurrency based on SQS queue depth

# Application Auto Scaling Target for Lambda provisioned concurrency
resource "aws_appautoscaling_target" "lambda_concurrency" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "function:${aws_lambda_function.process_object.function_name}:${aws_lambda_alias.process_object.name}"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  service_namespace  = "lambda"
}

# Auto Scaling Policy for high queue depth
resource "aws_appautoscaling_policy" "lambda_scale_up" {
  name               = "${var.name_prefix}-lambda-scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.lambda_concurrency.resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency.scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda_concurrency.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "SQSQueueMessagesVisiblePerTask"
      resource_label         = "${aws_sqs_queue.object_queue.name}/${aws_lambda_function.process_object.function_name}"
    }
    target_value       = 10.0 # Target 10 messages per Lambda instance
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 30   # 30 seconds
  }
}

# Lambda version resource to enable provisioned concurrency
resource "aws_lambda_alias" "process_object" {
  name             = "provisioned"
  function_name    = aws_lambda_function.process_object.function_name
  function_version = "$LATEST"
}

# Lambda provisioned concurrency
resource "aws_lambda_provisioned_concurrency_config" "process_object" {
  function_name                     = aws_lambda_function.process_object.function_name
  provisioned_concurrent_executions = aws_appautoscaling_target.lambda_concurrency.min_capacity
  qualifier                         = aws_lambda_alias.process_object.name
}
