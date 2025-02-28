"""AWS Lambda function to process objects from S3 buckets.

This function is the core processor for the S3 event processor pattern. It:
1. Reads objects from S3 buckets (primarily CSV files)
2. Processes each row with configurable batching and async options
3. Makes API calls to external services with simulated latency (5-30s)
4. Provides detailed logging for Splunk integration
5. Exports metrics for Dynatrace monitoring
6. Handles errors with proper status codes and DLQ integration

Part of the staggered invocation pattern implemented through Step Functions.
"""

import json
import logging
import os
from typing import Any, Dict

from .clients import APIClient, S3Client
from .errors import ValidationError
from .processors import CSVProcessor, S3ObjectProcessor
from .utils import validate_s3_details

# Configure logging
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","message":"%(message)s"}',
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
logger = logging.getLogger()


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """AWS Lambda handler function

    Expected event format:
    {
        "s3_details": {
            "bucket": "my-bucket",
            "key": "path/to/object.csv",
            "size": 12345,        # Optional, size in bytes
            "etag": "abc123"      # Optional, object ETag
        },
        "processing_options": {
            "use_async": true,
            "use_batch": true,
            "priority": "standard",   # Optional: "high", "standard", "low"
            "batch_size": 50,         # Optional, default is adaptive
            "chunked_processing": false # Optional, for large files
        },
        "source": "eventbridge",   # Optional, source of event
        "time": "2023-01-01T12:00:00Z", # Optional, event timestamp
        "id": "event-id-123"       # Optional, event ID
    }
    """
    logger.info(json.dumps({"action": "lambda_start", "event": event}))

    # Extract S3 object details
    try:
        s3_details = event.get("s3_details", {})
        processing_options = event.get("processing_options", {})
        event_source = event.get("source", "direct")
        event_time = event.get("time", "")
        event_id = event.get("id", "")

        # Validate S3 details
        validate_s3_details(s3_details)
        bucket = s3_details["bucket"]
        key = s3_details["key"]
        object_size = s3_details.get("size", 0)  # May be 0 if not provided
        object_etag = s3_details.get("etag", "")

        # Extract processing options
        use_async = processing_options.get("use_async", True)
        use_batch = processing_options.get("use_batch", True)
        priority = processing_options.get("priority", "standard")
        batch_size = processing_options.get("batch_size", None)  # None means adaptive
        chunked_processing = processing_options.get("chunked_processing", False)

        # Log extended details with structured format for Splunk and Dynatrace integration
        logger.info(
            json.dumps(
                {
                    "action": "processing_start",
                    "bucket": bucket,
                    "key": key,
                    "size": object_size,
                    "etag": object_etag,
                    "source": event_source,
                    "event_time": event_time,
                    "event_id": event_id,
                    "priority": priority,
                    "batch_size": batch_size,
                    "use_async": use_async,
                    "use_batch": use_batch,
                    "chunked_processing": chunked_processing,
                    # Structured metrics for Dynatrace integration
                    "dt.metrics": {
                        "object_size": object_size if object_size else 0,
                        "process_start": 1,
                        "priority_level": {"high": 3, "standard": 2, "low": 1}.get(priority, 2),
                    },
                    # Indexed fields for Splunk
                    "splunk.index": os.environ.get("SPLUNK_INDEX", "s3_processor"),
                    "splunk.sourcetype": "lambda:s3_processor",
                }
            )
        )

        # Initialize clients
        s3_client = S3Client()
        api_client = APIClient()
        csv_processor = CSVProcessor(api_client=api_client)

        # Create processor and process the object
        processor = S3ObjectProcessor(s3_client=s3_client, csv_processor=csv_processor)

        # Pass all processing options to the processor
        result = processor.process(
            bucket,
            key,
            use_async=use_async,
            use_batch=use_batch,
            priority=priority,
            batch_size=batch_size,
            chunked_processing=chunked_processing,
        )

        return result

    except ValidationError as e:
        # Log validation errors with structured data for better Splunk querying
        error_details = {
            "action": "validation_error",
            "error": str(e),
            "error_type": "ValidationError",
            "field": getattr(e, "field", None),
            "bucket": s3_details.get("bucket", "unknown"),
            "key": s3_details.get("key", "unknown"),
            "dt.metrics": {"validation_error": 1},
            "splunk.index": os.environ.get("SPLUNK_INDEX", "s3_processor"),
            "splunk.sourcetype": "lambda:s3_processor:error",
        }
        logger.error(json.dumps(error_details))
        return {
            "statusCode": 400,
            "body": f"Validation error: {e!s}",
            "error_details": error_details,
        }
    except Exception as e:
        # Comprehensive error logging for production monitoring
        import traceback

        error_traceback = traceback.format_exc()
        error_details = {
            "action": "lambda_error",
            "error": str(e),
            "error_type": e.__class__.__name__,
            "stack_trace": error_traceback,
            "bucket": s3_details.get("bucket", "unknown")
            if isinstance(s3_details, dict)
            else "unknown",
            "key": s3_details.get("key", "unknown") if isinstance(s3_details, dict) else "unknown",
            "dt.metrics": {
                "processing_error": 1,
                "error_category": 1,  # Metric for categorizing errors in Dynatrace
            },
            "splunk.index": os.environ.get("SPLUNK_INDEX", "s3_processor"),
            "splunk.sourcetype": "lambda:s3_processor:error",
        }
        logger.error(json.dumps(error_details))
        return {
            "statusCode": 500,
            "body": f"Error processing S3 object: {e!s}",
            "error_details": error_details,
        }


if __name__ == "__main__":
    # For local testing
    test_event = {
        "s3_details": {"bucket": "test-bucket", "key": "test/file.csv"},
        "processing_options": {"use_async": True, "use_batch": True},
    }
    print(lambda_handler(test_event, None))
