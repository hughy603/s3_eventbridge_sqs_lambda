/**
 * # Lambda Module
 *
 * This module creates a Lambda function with proper IAM roles,
 * provisioned concurrency, and auto-scaling for optimal performance.
 */

locals {
  lambda_zip_path = "${path.module}/lambda_function.zip"
}

# Create a zip deployment package for the Lambda function
data "archive_file" "lambda_package" {
  count       = var.create_package ? 1 : 0
  type        = "zip"
  source_dir  = var.source_dir
  output_path = local.lambda_zip_path
}

# Lambda function
resource "aws_lambda_function" "this" {
  function_name = "${var.name_prefix}-${var.function_name}"
  description   = var.description

  # Use either provided package or create one
  filename         = var.create_package ? local.lambda_zip_path : var.package_file
  source_code_hash = var.create_package ? data.archive_file.lambda_package[0].output_base64sha256 : var.package_hash

  handler = var.handler
  runtime = var.runtime

  timeout     = var.timeout
  memory_size = var.memory_size

  role = aws_iam_role.lambda.arn

  # X-Ray tracing
  tracing_config {
    mode = var.tracing_enabled ? "Active" : "PassThrough"
  }

  # Environment variables
  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${var.function_name}"
    }
  )
}

# Lambda function alias for provisioned concurrency
resource "aws_lambda_alias" "this" {
  name             = "provisioned"
  function_name    = aws_lambda_function.this.function_name
  function_version = "$LATEST"
}

# Lambda provisioned concurrency (if enabled)
resource "aws_lambda_provisioned_concurrency_config" "this" {
  count = var.provisioned_concurrency_enabled ? 1 : 0

  function_name                     = aws_lambda_function.this.function_name
  provisioned_concurrent_executions = var.provisioned_concurrency
  qualifier                         = aws_lambda_alias.this.name
}

# Dead letter configuration for Lambda failures (if enabled)
resource "aws_lambda_function_event_invoke_config" "this" {
  count = var.enable_function_dead_letter ? 1 : 0

  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.this.name

  destination_config {
    on_failure {
      destination = var.dead_letter_queue_arn
    }
  }
}

# CloudWatch Log Group with retention
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# IAM role for the Lambda function
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Basic Lambda execution permissions
resource "aws_iam_policy" "lambda_basic" {
  name        = "${var.name_prefix}-${var.function_name}-basic"
  description = "Basic Lambda execution permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# Attach basic policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_basic.arn
}

# X-Ray permissions if tracing is enabled
resource "aws_iam_policy" "lambda_xray" {
  count       = var.tracing_enabled ? 1 : 0
  name        = "${var.name_prefix}-${var.function_name}-xray"
  description = "Lambda X-Ray tracing permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach X-Ray policy if needed
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.tracing_enabled ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_xray[0].arn
}

# Additional IAM policies (if provided)
resource "aws_iam_policy" "lambda_additional" {
  count       = length(var.additional_policies) > 0 ? 1 : 0
  name        = "${var.name_prefix}-${var.function_name}-additional"
  description = "Additional Lambda permissions"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.additional_policies
  })
}

# Attach additional policies if needed
resource "aws_iam_role_policy_attachment" "lambda_additional" {
  count      = length(var.additional_policies) > 0 ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_additional[0].arn
}

# VPC configuration if provided
resource "aws_lambda_function_vpc_config" "this" {
  count              = var.subnet_ids != null && var.security_group_ids != null ? 1 : 0
  function_name      = aws_lambda_function.this.function_name
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
}

# Auto-scaling for provisioned concurrency
resource "aws_appautoscaling_target" "lambda_concurrency" {
  count              = var.auto_scaling_enabled ? 1 : 0
  max_capacity       = var.max_concurrency
  min_capacity       = var.provisioned_concurrency
  resource_id        = "function:${aws_lambda_function.this.function_name}:${aws_lambda_alias.this.name}"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  service_namespace  = "lambda"
}

# Scale based on utilization
resource "aws_appautoscaling_policy" "lambda_concurrency_utilization" {
  count              = var.auto_scaling_enabled ? 1 : 0
  name               = "${var.name_prefix}-${var.function_name}-utilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.lambda_concurrency[0].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "LambdaProvisionedConcurrencyUtilization"
    }
    target_value       = var.target_utilization
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Scale based on SQS queue depth if configured
resource "aws_appautoscaling_policy" "lambda_scale_sqs" {
  count              = var.auto_scaling_enabled && var.scale_based_on_sqs ? 1 : 0
  name               = "${var.name_prefix}-lambda-scale-sqs"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.lambda_concurrency[0].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "SQSQueueMessagesVisiblePerTask"
      resource_label         = "${var.sqs_queue_name}/${aws_lambda_function.this.function_name}"
    }
    target_value       = var.sqs_messages_per_function
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Monitoring alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-${var.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "Lambda function error rate"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-${var.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = var.throttle_threshold
  alarm_description   = "Lambda function throttles"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}
