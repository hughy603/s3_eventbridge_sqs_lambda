/**
 * Dynatrace Integration for S3 Event Processor
 *
 * This configuration integrates Dynatrace monitoring capabilities with
 * the S3 event processor module, enabling comprehensive metric monitoring.
 * Dynatrace is used as the primary metric monitoring tool.
 */

# Event rule to sync metrics with Dynatrace
resource "aws_cloudwatch_event_rule" "dynatrace_metric_sync" {
  count       = var.enable_dynatrace_integration ? 1 : 0
  name        = "${var.name_prefix}-dynatrace-metric-sync"
  description = "Trigger Dynatrace metric synchronization"

  # Run every 5 minutes to ensure metrics are synced regularly
  schedule_expression = "rate(5 minutes)"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-dynatrace-metric-sync"
  })
}

# Target the Dynatrace sync Lambda
resource "aws_cloudwatch_event_target" "dynatrace_metric_sync" {
  count = var.enable_dynatrace_integration ? 1 : 0
  rule  = aws_cloudwatch_event_rule.dynatrace_metric_sync[0].name
  arn   = var.dynatrace_sync_lambda_arn

  input = jsonencode({
    resources = {
      s3_bucket       = var.create_bucket ? module.s3_bucket[0].bucket_id : var.existing_bucket_id
      sqs_queue       = module.object_queue.queue_name
      lambda_function = module.lambda_function.function_name
      state_machine   = module.step_functions.state_machine_id
      event_rule      = module.eventbridge_rule.event_rule_id
      dlq             = module.lambda_dlq.queue_name
    }
    metrics = {
      include_custom_metrics     = true
      include_cloudwatch_metrics = false # Minimize CloudWatch usage
    }
  })
}

# Generate Dynatrace dashboard template
resource "local_file" "dynatrace_dashboard" {
  count    = var.generate_dynatrace_dashboard ? 1 : 0
  filename = "${path.root}/dynatrace/${var.name_prefix}-dashboard.json"
  content = templatefile("${path.module}/templates/dynatrace_dashboard.json.tftpl", {
    dashboard_name       = "${var.name_prefix}-s3-event-processor-dashboard"
    s3_bucket_name       = var.create_bucket ? module.s3_bucket[0].bucket_id : var.existing_bucket_id
    sqs_queue_name       = module.object_queue.queue_name
    lambda_function_name = module.lambda_function.function_name
    state_machine_arn    = module.step_functions.state_machine_arn
    event_rule_name      = module.eventbridge_rule.event_rule_id
    lambda_dlq_name      = module.lambda_dlq.queue_name
  })
}

# Add Dynatrace-specific tags to resources
locals {
  dynatrace_tags = var.enable_dynatrace_integration ? {
    DTMonitored      = "true"
    DTService        = var.lambda_function_name
    DTManagementZone = "S3EventProcessor"
  } : {}

  merged_tags = merge(var.tags, local.dynatrace_tags, local.splunk_tags)
}
