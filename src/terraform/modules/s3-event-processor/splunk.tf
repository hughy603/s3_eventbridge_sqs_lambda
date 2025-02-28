/**
 * Splunk Integration for S3 Event Processor
 *
 * This configuration integrates Splunk for log analytics,
 * minimizing CloudWatch usage outside of Lambda logging.
 */

resource "aws_cloudwatch_log_subscription_filter" "splunk_lambda_logs" {
  count           = var.enable_splunk_integration ? 1 : 0
  name            = "${var.name_prefix}-splunk-lambda-filter"
  log_group_name  = "/aws/lambda/${module.lambda_function.function_name}"
  filter_pattern  = "" # Capture all logs
  destination_arn = var.splunk_forwarder_lambda_arn

  # This tells Lambda to forward logs in JSON format
  distribution = "Random"
}

resource "aws_cloudwatch_log_subscription_filter" "splunk_step_functions_logs" {
  count           = var.enable_splunk_integration ? 1 : 0
  name            = "${var.name_prefix}-splunk-sf-filter"
  log_group_name  = "/aws/states/${module.step_functions.state_machine_id}"
  filter_pattern  = "" # Capture all logs
  destination_arn = var.splunk_forwarder_lambda_arn

  distribution = "Random"
}

# IAM permissions to allow Splunk forwarder Lambda to access logs
resource "aws_lambda_permission" "allow_cloudwatch_to_invoke_splunk_forwarder_lambda" {
  count         = var.enable_splunk_integration ? 1 : 0
  statement_id  = "AllowExecutionFromCloudWatch-${var.name_prefix}"
  action        = "lambda:InvokeFunction"
  function_name = var.splunk_forwarder_lambda_arn
  principal     = "logs.amazonaws.com"
  source_arn    = "/aws/lambda/${module.lambda_function.function_name}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_invoke_splunk_forwarder_sf" {
  count         = var.enable_splunk_integration ? 1 : 0
  statement_id  = "AllowExecutionFromCloudWatch-SF-${var.name_prefix}"
  action        = "lambda:InvokeFunction"
  function_name = var.splunk_forwarder_lambda_arn
  principal     = "logs.amazonaws.com"
  source_arn    = "/aws/states/${module.step_functions.state_machine_id}"
}

# Add specific tags to Lambda function to help with Splunk categorization
locals {
  splunk_tags = var.enable_splunk_integration ? {
    SplunkIndex  = var.splunk_index_name
    LogAnalytics = "Splunk"
    SourceType   = "aws:lambda:s3processor"
  } : {}
}
