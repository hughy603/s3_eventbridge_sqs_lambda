/**
 * # S3 EventBridge SQS Lambda Pipeline
 *
 * This solution creates a pipeline that processes S3 objects through EventBridge,
 * SQS, Step Functions, and Lambda for reliable and scalable event processing.
 */

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment this block to use a remote backend like S3
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "s3-eventbridge-sqs-lambda/terraform.tfstate"
  #   region = "us-east-1"
  # }
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
    Application = "Object Processor"
    Owner       = "Your Team"
  }
}

# S3 Bucket Module
module "s3_bucket" {
  source      = "./modules/s3"
  name_prefix = var.name_prefix
  tags        = local.tags

  # Configure S3 security settings
  enable_versioning                  = true
  access_log_bucket_name             = null # Set to a logging bucket if needed
  enable_lifecycle_rules             = true
  noncurrent_version_expiration_days = 30
}

# SQS Queue Module for object events
module "object_queue" {
  source      = "./modules/sqs"
  name_prefix = var.name_prefix
  queue_name  = "object-queue"
  tags        = local.tags

  # Configure SQS settings
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 300
  max_receive_count          = 3

  # Configure permissions for EventBridge
  allowed_actions    = ["sqs:SendMessage"]
  principal_services = ["events.amazonaws.com"]
  source_arns        = [module.eventbridge_rule.event_rule_arn]

  # Configure alarms
  create_alarms          = true
  queue_depth_threshold  = 100
  dlq_messages_threshold = 1
  alarm_actions          = []
}

# EventBridge Module
module "eventbridge_rule" {
  source      = "./modules/eventbridge"
  name_prefix = var.name_prefix
  bucket_id   = module.s3_bucket.bucket_id
  queue_arn   = module.object_queue.queue_arn
  tags        = local.tags
}

# Lambda Function Module
module "process_object_lambda" {
  source        = "./modules/lambda"
  name_prefix   = var.name_prefix
  function_name = "process-object"
  description   = "Process objects from S3"
  tags          = local.tags

  # Function configuration
  handler     = "process_object.lambda_handler"
  runtime     = "python3.12"
  timeout     = 900
  memory_size = 512

  # Package configuration
  create_package = true
  source_dir     = "${path.module}/../../python/functions"

  # Environment variables
  environment_variables = {
    LOG_LEVEL = "INFO"
  }

  # Auto-scaling configuration
  provisioned_concurrency_enabled = true
  provisioned_concurrency         = 5
  auto_scaling_enabled            = true
  max_concurrency                 = 100
  target_utilization              = 0.7
  scale_in_cooldown               = 300
  scale_out_cooldown              = 30

  # SQS scaling
  scale_based_on_sqs        = true
  sqs_queue_name            = module.object_queue.queue_name
  sqs_messages_per_function = 10

  # Lambda additional permissions for S3 access
  additional_policies = [
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectTagging"
      ]
      Resource = "${module.s3_bucket.bucket_arn}/*"
    }
  ]

  # DLQ configuration
  enable_function_dead_letter = true
  dead_letter_queue_arn       = module.lambda_dlq.queue_arn

  # Tracing and monitoring
  tracing_enabled    = true
  log_retention_days = 30
  create_alarms      = true
  error_threshold    = 1
  throttle_threshold = 1
  alarm_actions      = []
}

# SQS Queue Module for Lambda DLQ
module "lambda_dlq" {
  source      = "./modules/sqs"
  name_prefix = var.name_prefix
  queue_name  = "lambda-dlq"
  tags        = local.tags

  # Configure SQS settings
  message_retention_seconds = 1209600

  # Configure permissions (no external services can send messages)
  allowed_actions    = []
  principal_services = []

  # Configure alarms
  create_alarms          = true
  dlq_messages_threshold = 1
  alarm_actions          = []
}

# Step Functions Module
module "step_functions" {
  source             = "./modules/step_functions"
  name_prefix        = var.name_prefix
  state_machine_name = "process-objects"
  tags               = local.tags

  # Step Functions definition
  definition = <<EOF
{
  "Comment": "Process objects from SQS in a staggered manner",
  "StartAt": "GetMessagesFromQueue",
  "States": {
    "GetMessagesFromQueue": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:receiveMessage",
      "Parameters": {
        "QueueUrl": "${module.object_queue.queue_url}",
        "MaxNumberOfMessages": 10,
        "WaitTimeSeconds": 10
      },
      "Next": "CheckForMessages",
      "ResultPath": "$.messages",
      "Retry": [
        {
          "ErrorEquals": ["States.ALL"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "SendToStepFunctionsDLQ"
        }
      ]
    },
    "SendToStepFunctionsDLQ": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage",
      "Parameters": {
        "QueueUrl": "${module.step_functions.dlq_url}",
        "MessageBody": {
          "error.$": "$.error",
          "timestamp.$": "$$.Execution.StartTime",
          "executionArn.$": "$$.Execution.Id"
        }
      },
      "Next": "Wait"
    },
    "CheckForMessages": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.messages.Messages[0]",
          "IsPresent": true,
          "Next": "GetQueueAttributes"
        }
      ],
      "Default": "Wait"
    },
    "Wait": {
      "Type": "Wait",
      "Seconds": 10,
      "Next": "GetMessagesFromQueue"
    },
    "GetQueueAttributes": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:sqs:getQueueAttributes",
      "Parameters": {
        "QueueUrl": "${module.object_queue.queue_url}",
        "AttributeNames": ["ApproximateNumberOfMessages"]
      },
      "ResultPath": "$.queue_attributes",
      "Next": "CalculateMaxConcurrency"
    },
    "CalculateMaxConcurrency": {
      "Type": "Pass",
      "Parameters": {
        "messages.$": "$.messages",
        "queue_attributes.$": "$.queue_attributes",
        "max_concurrency.$": "States.MathMax(3, States.MathMin(25, States.MathFloor($.queue_attributes.Attributes.ApproximateNumberOfMessages / 10)))"
      },
      "Next": "ProcessMessages"
    },
    "ProcessMessages": {
      "Type": "Map",
      "ItemsPath": "$.messages.Messages",
      "MaxConcurrencyPath": "$.max_concurrency",
      "Iterator": {
        "StartAt": "ParseMessage",
        "States": {
          "ParseMessage": {
            "Type": "Pass",
            "Parameters": {
              "message.$": "$",
              "body.$": "$.Body"
            },
            "Next": "ParseBody"
          },
          "ParseBody": {
            "Type": "Pass",
            "Parameters": {
              "body.$": "States.StringToJson($.body)"
            },
            "Next": "PrepareS3Details",
            "Catch": [
              {
                "ErrorEquals": ["States.ALL"],
                "ResultPath": "$.error",
                "Next": "SendToParsingDLQ"
              }
            ]
          },
          "SendToParsingDLQ": {
            "Type": "Task",
            "Resource": "arn:aws:states:::sqs:sendMessage",
            "Parameters": {
              "QueueUrl": "${module.step_functions.dlq_url}",
              "MessageBody": {
                "error.$": "$.error",
                "message.$": "$.message",
                "stage": "parsing",
                "timestamp.$": "$$.Execution.StartTime"
              }
            },
            "Next": "DeleteMessage"
          },
          "PrepareS3Details": {
            "Type": "Pass",
            "Parameters": {
              "message_id.$": "$.message.MessageId",
              "receipt_handle.$": "$.message.ReceiptHandle",
              "s3_details": {
                "bucket.$": "$.body.detail.bucket.name",
                "key.$": "$.body.detail.object.key"
              }
            },
            "Next": "StaggeredWait"
          },
          "StaggeredWait": {
            "Type": "Wait",
            "SecondsPath": "$$.Map.Item.Index",
            "Next": "InvokeLambda"
          },
          "InvokeLambda": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke",
            "Parameters": {
              "FunctionName": "${module.process_object_lambda.function_name}",
              "Payload": {
                "s3_details.$": "$.s3_details"
              }
            },
            "Next": "DeleteMessage",
            "Retry": [
              {
                "ErrorEquals": ["States.ALL"],
                "IntervalSeconds": 2,
                "MaxAttempts": 3,
                "BackoffRate": 2
              }
            ],
            "Catch": [
              {
                "ErrorEquals": ["States.ALL"],
                "Next": "RecordError"
              }
            ],
            "ResultPath": "$.lambda_result"
          },
          "RecordError": {
            "Type": "Pass",
            "Parameters": {
              "error.$": "$$.State.Error",
              "cause.$": "$$.State.ErrorCause",
              "message_id.$": "$.message_id",
              "s3_details.$": "$.s3_details"
            },
            "Next": "SendToLambdaDLQ"
          },
          "SendToLambdaDLQ": {
            "Type": "Task",
            "Resource": "arn:aws:states:::sqs:sendMessage",
            "Parameters": {
              "QueueUrl": "${module.lambda_dlq.queue_url}",
              "MessageBody": {
                "error.$": "$.error",
                "cause.$": "$.cause",
                "s3_details.$": "$.s3_details",
                "message_id.$": "$.message_id",
                "stage": "lambda_invocation",
                "timestamp.$": "$$.Execution.StartTime"
              }
            },
            "Next": "DeleteMessage"
          },
          "DeleteMessage": {
            "Type": "Task",
            "Resource": "arn:aws:states:::sqs:deleteMessage",
            "Parameters": {
              "QueueUrl": "${module.object_queue.queue_url}",
              "ReceiptHandle.$": "$.receipt_handle"
            },
            "End": true
          }
        }
      },
      "Next": "GetMessagesFromQueue"
    }
  }
}
EOF

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
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics"
      ]
      Resource = "*"
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
      Resource = module.process_object_lambda.function_arn
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
  enable_scheduled_execution = true
  schedule_expression        = "rate(1 minute)"

  # Monitoring configuration
  log_retention_days = 30
  create_alarms      = true
  failure_threshold  = 1
  timeout_threshold  = 1
  alarm_actions      = []
  create_dashboard   = true
}
