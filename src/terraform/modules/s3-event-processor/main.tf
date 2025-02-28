/**
 * # S3 Event Processor
 *
 * This module creates a reusable pattern for staggered processing of S3 object events.
 * It handles S3 bucket events, routes them through EventBridge to SQS, and uses
 * Step Functions to invoke Lambda functions in a staggered manner to prevent
 * overloading of backend resources.
 *
 * Monitoring Strategy:
 * - Dynatrace as primary metric monitoring tool
 * - Splunk for log analytics
 * - Minimal use of CloudWatch outside of Lambda logging
 */

locals {
  # Combine tags from all sources
  tags = merge(var.tags, {
    Module = "s3-event-processor"
  })
}

# S3 Bucket Module
module "s3_bucket" {
  count       = var.create_bucket ? 1 : 0
  source      = "../s3"
  name_prefix = var.name_prefix
  tags        = local.merged_tags

  # Configure S3 security settings
  enable_versioning                  = var.s3_enable_versioning
  access_log_bucket_name             = var.s3_access_log_bucket_name
  enable_lifecycle_rules             = var.s3_enable_lifecycle_rules
  noncurrent_version_expiration_days = var.s3_noncurrent_version_expiration_days
}

# SQS Queue Module for object events
module "object_queue" {
  source      = "../sqs"
  name_prefix = var.name_prefix
  queue_name  = var.sqs_queue_name
  tags        = local.merged_tags

  # Configure SQS settings
  delay_seconds              = var.sqs_delay_seconds
  max_message_size           = var.sqs_max_message_size
  message_retention_seconds  = var.sqs_message_retention_seconds
  receive_wait_time_seconds  = var.sqs_receive_wait_time_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  max_receive_count          = var.sqs_max_receive_count

  # Configure permissions for EventBridge
  allowed_actions    = ["sqs:SendMessage"]
  principal_services = ["events.amazonaws.com"]
  source_arns        = [module.eventbridge_rule.event_rule_arn]

  # Configure alarms (only create CloudWatch alarms if needed)
  create_alarms          = var.create_alarms
  queue_depth_threshold  = var.sqs_queue_depth_threshold
  dlq_messages_threshold = var.sqs_dlq_messages_threshold
  alarm_actions          = var.alarm_actions
}

# EventBridge Module
module "eventbridge_rule" {
  source      = "../eventbridge"
  name_prefix = var.name_prefix
  bucket_id   = var.create_bucket ? module.s3_bucket[0].bucket_id : var.existing_bucket_id
  queue_arn   = module.object_queue.queue_arn
  tags        = local.merged_tags
}

# Lambda Function Module
module "lambda_function" {
  source        = "../lambda"
  name_prefix   = var.name_prefix
  function_name = var.lambda_function_name
  description   = var.lambda_description
  tags          = local.merged_tags

  # Function configuration
  handler     = var.lambda_handler
  runtime     = var.lambda_runtime
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  # Package configuration
  create_package = var.lambda_create_package
  source_dir     = var.lambda_source_dir
  filename       = var.lambda_filename
  s3_bucket      = var.lambda_s3_bucket
  s3_key         = var.lambda_s3_key

  # Environment variables
  environment_variables = var.lambda_environment_variables

  # Auto-scaling configuration
  provisioned_concurrency_enabled = var.lambda_provisioned_concurrency_enabled
  provisioned_concurrency         = var.lambda_provisioned_concurrency
  auto_scaling_enabled            = var.lambda_auto_scaling_enabled
  max_concurrency                 = var.lambda_max_concurrency
  target_utilization              = var.lambda_target_utilization
  scale_in_cooldown               = var.lambda_scale_in_cooldown
  scale_out_cooldown              = var.lambda_scale_out_cooldown

  # SQS scaling
  scale_based_on_sqs        = var.lambda_scale_based_on_sqs
  sqs_queue_name            = module.object_queue.queue_name
  sqs_messages_per_function = var.lambda_sqs_messages_per_function

  # Lambda additional permissions for S3 access
  additional_policies = concat([
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectTagging"
      ]
      Resource = var.create_bucket ? "${module.s3_bucket[0].bucket_arn}/*" : "${var.existing_bucket_arn}/*"
    }
  ], var.lambda_additional_policies)

  # DLQ configuration
  enable_function_dead_letter = var.lambda_enable_function_dead_letter
  dead_letter_queue_arn       = module.lambda_dlq.queue_arn

  # Tracing and monitoring
  tracing_enabled    = var.lambda_tracing_enabled
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_alarms
  error_threshold    = var.lambda_error_threshold
  throttle_threshold = var.lambda_throttle_threshold
  alarm_actions      = var.alarm_actions

  # Use CloudWatch dashboards only if explicitly requested
  create_dashboard = var.create_dashboard
}

# SQS Queue Module for Lambda DLQ
module "lambda_dlq" {
  source      = "../sqs"
  name_prefix = var.name_prefix
  queue_name  = "${var.lambda_function_name}-dlq"
  tags        = local.merged_tags

  # Configure SQS settings
  message_retention_seconds = var.sqs_message_retention_seconds

  # Configure permissions (no external services can send messages)
  allowed_actions    = []
  principal_services = []

  # Configure alarms (only create CloudWatch alarms if needed)
  create_alarms          = var.create_alarms
  dlq_messages_threshold = var.sqs_dlq_messages_threshold
  alarm_actions          = var.alarm_actions
}

# Step Functions Module
module "step_functions" {
  source             = "../step_functions"
  name_prefix        = var.name_prefix
  state_machine_name = var.step_functions_name
  tags               = local.merged_tags

  # Step Functions definition
  definition = templatefile("${path.module}/templates/staggered_processing.json.tftpl", {
    sqs_queue_url          = module.object_queue.queue_url
    sqs_queue_arn          = module.object_queue.queue_arn
    lambda_function_name   = module.lambda_function.function_name
    lambda_function_arn    = module.lambda_function.function_arn
    step_functions_dlq_url = module.step_functions.dlq_url
    step_functions_dlq_arn = module.step_functions.dlq_arn
    lambda_dlq_url         = module.lambda_dlq.queue_url
    lambda_dlq_arn         = module.lambda_dlq.queue_arn
    max_concurrency        = var.step_functions_max_concurrency
  })

  # Permissions needed by Step Functions
  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = module.object_queue.queue_arn
    },
    {
      Effect = "Allow"
      Action = [
        "sqs:SendMessage"
      ]
      Resource = [
        module.step_functions.dlq_arn,
        module.lambda_dlq.queue_arn
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction"
      ]
      Resource = module.lambda_function.function_arn
    },
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }
  ]

  # Schedule configuration
  enable_scheduled_execution = var.step_functions_enable_scheduled_execution
  schedule_expression        = var.step_functions_schedule_expression

  # Monitoring configuration
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_alarms
  failure_threshold  = var.step_functions_failure_threshold
  timeout_threshold  = var.step_functions_timeout_threshold
  alarm_actions      = var.alarm_actions
  create_dashboard   = var.create_dashboard
}
