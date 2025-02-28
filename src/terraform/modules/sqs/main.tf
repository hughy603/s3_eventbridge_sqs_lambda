/**
 * # SQS Module
 *
 * This module creates SQS queues with proper configurations,
 * including dead-letter queues and necessary IAM policies.
 */

# Main SQS Queue
resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-${var.queue_name}"
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Encryption
  sqs_managed_sse_enabled = true

  # Dead-letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${var.queue_name}"
    }
  )
}

# Dead-Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-${var.queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  # Encryption
  sqs_managed_sse_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${var.queue_name}-dlq"
    }
  )
}

# IAM policy document for the main queue
data "aws_iam_policy_document" "queue_policy" {
  statement {
    effect    = "Allow"
    actions   = var.allowed_actions
    resources = [aws_sqs_queue.main.arn]

    principals {
      type        = "Service"
      identifiers = var.principal_services
    }

    # Add condition if EventBridge rule ARN is provided
    dynamic "condition" {
      for_each = var.source_arns != null ? [1] : []
      content {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = var.source_arns
      }
    }
  }
}

# Attach policy to the queue
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.url
  policy    = data.aws_iam_policy_document.queue_policy.json
}

# CloudWatch Alarm for queue depth
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-${var.queue_name}-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.queue_depth_threshold
  alarm_description   = "Alarm when queue depth exceeds threshold"

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}

# CloudWatch Alarm for DLQ messages
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-${var.queue_name}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.dlq_messages_threshold
  alarm_description   = "Alarm when DLQ has messages"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}
