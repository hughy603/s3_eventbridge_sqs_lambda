/**
 * # Step Functions Module
 *
 * This module creates a Step Functions state machine with proper IAM roles,
 * DLQ configuration, and monitoring.
 */

# SQS Queue for Step Functions DLQ
resource "aws_sqs_queue" "step_functions_dlq" {
  name                      = "${var.name_prefix}-step-functions-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  # Encryption
  sqs_managed_sse_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-step-functions-dlq"
    }
  )
}

# CloudWatch Event to trigger Step Functions on a schedule (if enabled)
resource "aws_cloudwatch_event_rule" "trigger_step_functions" {
  count               = var.enable_scheduled_execution ? 1 : 0
  name                = "${var.name_prefix}-trigger-step-functions"
  description         = "Trigger Step Functions state machine on a schedule"
  schedule_expression = var.schedule_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "trigger_step_functions" {
  count     = var.enable_scheduled_execution ? 1 : 0
  rule      = aws_cloudwatch_event_rule.trigger_step_functions[0].name
  target_id = "TriggerStepFunctions"
  arn       = aws_sfn_state_machine.this.arn
  role_arn  = aws_iam_role.cloudwatch_events[0].arn
}

# IAM role for CloudWatch Events
resource "aws_iam_role" "cloudwatch_events" {
  count = var.enable_scheduled_execution ? 1 : 0
  name  = "${var.name_prefix}-cloudwatch-events-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# CloudWatch Events policy
resource "aws_iam_policy" "cloudwatch_events" {
  count       = var.enable_scheduled_execution ? 1 : 0
  name        = "${var.name_prefix}-cloudwatch-events-policy"
  description = "Allow CloudWatch Events to start Step Functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.this.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_events" {
  count      = var.enable_scheduled_execution ? 1 : 0
  role       = aws_iam_role.cloudwatch_events[0].name
  policy_arn = aws_iam_policy.cloudwatch_events[0].arn
}

# Step Functions state machine
resource "aws_sfn_state_machine" "this" {
  name       = "${var.name_prefix}-${var.state_machine_name}"
  role_arn   = aws_iam_role.step_functions.arn
  definition = var.definition

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${var.state_machine_name}"
    }
  )
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${var.name_prefix}-${var.state_machine_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions" {
  name = "${var.name_prefix}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Step Functions policies
resource "aws_iam_policy" "step_functions" {
  name        = "${var.name_prefix}-step-functions-policy"
  description = "Allow Step Functions to interact with other services"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}

resource "aws_iam_role_policy_attachment" "step_functions" {
  role       = aws_iam_role.step_functions.name
  policy_arn = aws_iam_policy.step_functions.arn
}

# CloudWatch Alarms for Step Functions
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-step-functions-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 60
  statistic           = "Sum"
  threshold           = var.failure_threshold
  alarm_description   = "Alarm when Step Functions executions fail"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.this.arn
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "step_functions_timeouts" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name_prefix}-step-functions-timeouts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = 60
  statistic           = "Sum"
  threshold           = var.timeout_threshold
  alarm_description   = "Alarm when Step Functions executions time out"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.this.arn
  }

  actions_enabled = true
  alarm_actions   = var.alarm_actions
  ok_actions      = var.ok_actions

  tags = var.tags
}

# CloudWatch Dashboard for Step Functions
resource "aws_cloudwatch_dashboard" "step_functions" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "${var.name_prefix}-step-functions-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.this.arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.this.arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.this.arn],
            ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", aws_sfn_state_machine.this.arn]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions Executions"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionThrottled", "StateMachineArn", aws_sfn_state_machine.this.arn]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions Throttling"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { "stat" : "Average" }],
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { "stat" : "Maximum" }],
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { "stat" : "p90" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions Execution Time (ms)"
          period  = 60
        }
      }
    ]
  })
}

# Data source for current region
data "aws_region" "current" {}
