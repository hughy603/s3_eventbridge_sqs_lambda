# CloudWatch Alarms for monitoring the health of the pipeline

# Alarm for SQS queue depth
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${var.name_prefix}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "This alarm monitors SQS queue depth"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.object_queue.name
  }

  tags = {
    Name = "${var.name_prefix}-sqs-queue-depth"
  }
}

# Alarm for SQS DLQ messages
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${var.name_prefix}-sqs-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors SQS DLQ for any messages"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.object_queue_dlq.name
  }

  tags = {
    Name = "${var.name_prefix}-sqs-dlq-messages"
  }
}

# Alarm for Step Functions DLQ messages
resource "aws_cloudwatch_metric_alarm" "step_functions_dlq_messages" {
  alarm_name          = "${var.name_prefix}-step-functions-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Step Functions DLQ for any messages"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.step_functions_dlq.name
  }

  tags = {
    Name = "${var.name_prefix}-step-functions-dlq-messages"
  }
}

# Alarm for Lambda DLQ messages
resource "aws_cloudwatch_metric_alarm" "lambda_dlq_messages" {
  alarm_name          = "${var.name_prefix}-lambda-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Lambda DLQ for any messages"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.lambda_dlq.name
  }

  tags = {
    Name = "${var.name_prefix}-lambda-dlq-messages"
  }
}

# Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Lambda errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.process_object.function_name
  }

  tags = {
    Name = "${var.name_prefix}-lambda-errors"
  }
}

# Alarm for Step Functions execution failures
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  alarm_name          = "${var.name_prefix}-step-functions-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Step Functions execution failures"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.process_objects.arn
  }

  tags = {
    Name = "${var.name_prefix}-step-functions-failures"
  }
}

# Alarm for Lambda throttles (for auto-scaling)
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name_prefix}-lambda-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Lambda throttles for auto-scaling"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.process_object.function_name
  }

  tags = {
    Name = "${var.name_prefix}-lambda-throttles"
  }
}

# SNS Topic for CloudWatch alarms
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}
