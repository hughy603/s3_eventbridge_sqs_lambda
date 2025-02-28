/**
 * # EventBridge Module
 *
 * This module creates EventBridge rules to capture S3 events
 * and route them to an SQS queue with advanced content-based filtering.
 */

# EventBridge rule to capture S3 object creation events with content-based filtering
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${var.name_prefix}-s3-object-created"
  description = "Capture S3 object creation events with advanced filtering"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.bucket_id]
      }
      object = {
        key = [{
          prefix = var.key_prefix != null ? var.key_prefix : ""
        }]
        size = [{
          numeric = [">=", var.min_size_bytes != null ? var.min_size_bytes : 0]
        }]
        etag = [{
          exists = true
        }]
      }
      reason = [
        "PutObject",
        "CompleteMultipartUpload",
        "CopyObject"
      ]
    }
  })

  tags = var.tags
}

# Rule for high priority processing (CSV files)
resource "aws_cloudwatch_event_rule" "s3_csv_created" {
  count       = var.enable_content_filtering ? 1 : 0
  name        = "${var.name_prefix}-s3-csv-created"
  description = "Capture S3 CSV file creation events"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.bucket_id]
      }
      object = {
        key = [{
          suffix = ".csv"
        }]
      }
    }
  })

  tags = var.tags
}

# Rule for large files (over 100MB)
resource "aws_cloudwatch_event_rule" "s3_large_object_created" {
  count       = var.enable_content_filtering ? 1 : 0
  name        = "${var.name_prefix}-s3-large-object-created"
  description = "Capture large S3 object creation events"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.bucket_id]
      }
      object = {
        size = [{
          numeric = [">=", 104857600] # 100MB in bytes
        }]
      }
    }
  })

  tags = var.tags
}

# Target for standard processing
resource "aws_cloudwatch_event_target" "s3_events_to_sqs" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "SendToSQS"
  arn       = var.queue_arn

  # Add event processing metadata
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      etag   = "$.detail.object.etag"
      time   = "$.time"
      id     = "$.id"
    }
    input_template = <<EOF
{
  "source": "eventbridge",
  "time": <time>,
  "id": <id>,
  "s3_details": {
    "bucket": <bucket>,
    "key": <key>,
    "size": <size>,
    "etag": <etag>
  },
  "processing_options": {
    "use_async": true,
    "use_batch": true,
    "priority": "standard"
  }
}
EOF
  }
}

# Target for high priority (CSV) queue
resource "aws_cloudwatch_event_target" "csv_events_to_priority_sqs" {
  count     = var.enable_content_filtering ? 1 : 0
  rule      = aws_cloudwatch_event_rule.s3_csv_created[0].name
  target_id = "SendToPrioritySQS"
  arn       = var.priority_queue_arn != null ? var.priority_queue_arn : var.queue_arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      time   = "$.time"
      id     = "$.id"
    }
    input_template = <<EOF
{
  "source": "eventbridge",
  "time": <time>,
  "id": <id>,
  "s3_details": {
    "bucket": <bucket>,
    "key": <key>,
    "size": <size>
  },
  "processing_options": {
    "use_async": true,
    "use_batch": true,
    "priority": "high",
    "batch_size": 50
  }
}
EOF
  }
}

# Target for large file queue
resource "aws_cloudwatch_event_target" "large_file_events_to_sqs" {
  count     = var.enable_content_filtering ? 1 : 0
  rule      = aws_cloudwatch_event_rule.s3_large_object_created[0].name
  target_id = "SendToLargeFileSQS"
  arn       = var.large_file_queue_arn != null ? var.large_file_queue_arn : var.queue_arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      time   = "$.time"
      id     = "$.id"
    }
    input_template = <<EOF
{
  "source": "eventbridge",
  "time": <time>,
  "id": <id>,
  "s3_details": {
    "bucket": <bucket>,
    "key": <key>,
    "size": <size>
  },
  "processing_options": {
    "use_async": true,
    "use_batch": true,
    "priority": "low",
    "batch_size": 200,
    "chunked_processing": true
  }
}
EOF
  }
}
