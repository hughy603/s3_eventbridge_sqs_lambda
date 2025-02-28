/**
 * # Example: S3 Event Processor
 *
 * This example demonstrates how to use the s3-event-processor module
 * to create a staggered Lambda invocation pattern for processing S3 objects.
 * - Uses Dynatrace for metric monitoring
 * - Uses Splunk for log analytics
 * - Minimizes CloudWatch use outside of Lambda logging
 */

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "S3-EventBridge-SQS-Lambda"
      Environment = var.environment
      Terraform   = "true"
    }
  }
}

# Common tags for all resources
locals {
  tags = {
    Application = "Object Processor Example"
    Owner       = "DevOps Team"
  }
}

# Simulated Dynatrace metric sync Lambda (for demonstration purposes)
# In a real scenario, you would use an actual Dynatrace integration Lambda
resource "aws_lambda_function" "dynatrace_sync" {
  function_name = "${var.name_prefix}-dynatrace-sync"
  role          = aws_iam_role.dynatrace_sync.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30

  filename = "${path.module}/files/dummy_lambda.zip"

  environment {
    variables = {
      DYNATRACE_URL = "https://example.dynatrace.com"
    }
  }

  tags = local.tags
}

resource "aws_iam_role" "dynatrace_sync" {
  name = "${var.name_prefix}-dynatrace-sync-role"

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

  tags = local.tags
}

resource "aws_iam_role_policy" "dynatrace_sync" {
  name = "${var.name_prefix}-dynatrace-sync-policy"
  role = aws_iam_role.dynatrace_sync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Simulated Splunk forwarder Lambda (for demonstration purposes)
# In a real scenario, you would use an actual Splunk forwarder Lambda
resource "aws_lambda_function" "splunk_forwarder" {
  function_name = "${var.name_prefix}-splunk-forwarder"
  role          = aws_iam_role.splunk_forwarder.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30

  filename = "${path.module}/files/dummy_lambda.zip"

  environment {
    variables = {
      SPLUNK_HEC_URL = "https://splunk-hec.example.com:8088"
      SPLUNK_INDEX   = "aws_lambda"
    }
  }

  tags = local.tags
}

resource "aws_iam_role" "splunk_forwarder" {
  name = "${var.name_prefix}-splunk-forwarder-role"

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

  tags = local.tags
}

resource "aws_iam_role_policy" "splunk_forwarder" {
  name = "${var.name_prefix}-splunk-forwarder-policy"
  role = aws_iam_role.splunk_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Using the s3-event-processor module with a new S3 bucket
module "process_objects" {
  source = "../modules/s3-event-processor"

  name_prefix = var.name_prefix
  tags        = local.tags

  # Lambda Configuration
  lambda_function_name = "process-object"
  lambda_handler       = "process_object.lambda_handler"
  lambda_runtime       = "python3.12"
  lambda_source_dir    = "${path.module}/../../python/functions"
  lambda_memory_size   = 512
  lambda_timeout       = 900

  lambda_environment_variables = {
    LOG_LEVEL = "INFO"
    # Add Dynatrace environment variables for OneAgent integration
    DT_CUSTOM_PROP = "keptn_project=s3-processor,keptn_service=object-processor"
    DT_CLUSTER_ID  = "s3-processor-cluster"
  }

  # Auto-scaling configuration
  lambda_provisioned_concurrency_enabled = true
  lambda_provisioned_concurrency         = 5
  lambda_auto_scaling_enabled            = true
  lambda_max_concurrency                 = 100

  # Step Functions Configuration
  step_functions_name                = "process-objects"
  step_functions_max_concurrency     = 3
  step_functions_schedule_expression = "rate(1 minute)"

  # Dynatrace Integration
  enable_dynatrace_integration = true
  generate_dynatrace_dashboard = true
  dynatrace_sync_lambda_arn    = aws_lambda_function.dynatrace_sync.arn

  # Splunk Integration
  enable_splunk_integration   = true
  splunk_forwarder_lambda_arn = aws_lambda_function.splunk_forwarder.arn
  splunk_index_name           = "s3_processor"

  # Minimize CloudWatch usage
  create_dashboard = false

  # Keep only critical CloudWatch alarms
  create_alarms = true
  alarm_actions = []
}

# Example of using the module with an existing bucket
module "process_objects_existing_bucket" {
  source = "../modules/s3-event-processor"

  name_prefix = "${var.name_prefix}-existing"
  tags        = local.tags

  # Use existing S3 bucket
  create_bucket       = false
  existing_bucket_id  = "my-existing-bucket"              # Replace with your bucket ID
  existing_bucket_arn = "arn:aws:s3:::my-existing-bucket" # Replace with your bucket ARN

  # Lambda Configuration
  lambda_function_name = "process-existing-bucket-object"
  lambda_handler       = "process_object.lambda_handler"
  lambda_runtime       = "python3.12"
  lambda_source_dir    = "${path.module}/../../python/functions"

  # Set Lambda auto-scaling based on SQS queue depth
  lambda_scale_based_on_sqs        = true
  lambda_sqs_messages_per_function = 10

  # Lambda environment variables for Dynatrace integration
  lambda_environment_variables = {
    LOG_LEVEL      = "INFO"
    DT_CUSTOM_PROP = "keptn_project=s3-processor,keptn_service=existing-bucket-processor"
    DT_CLUSTER_ID  = "s3-processor-cluster"
  }

  # Step Functions with higher concurrency
  step_functions_max_concurrency = 5

  # Dynatrace Integration
  enable_dynatrace_integration = true
  generate_dynatrace_dashboard = true
  dynatrace_sync_lambda_arn    = aws_lambda_function.dynatrace_sync.arn

  # Splunk Integration
  enable_splunk_integration   = true
  splunk_forwarder_lambda_arn = aws_lambda_function.splunk_forwarder.arn
  splunk_index_name           = "s3_processor_existing"

  # Minimize CloudWatch usage
  create_dashboard = false
}
