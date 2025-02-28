"""Client classes for external services"""

import json
import logging
import random
import time
from typing import Any, Optional

from .aws_clients import AWSClients
from .errors import APIError, S3Error
from .utils import CircuitBreaker, retry

logger = logging.getLogger(__name__)


class S3Client:
    """S3 client for interacting with S3 buckets"""

    def __init__(self, s3_client=None):
        """Initialize with optional client for dependency injection"""
        self._s3_client = s3_client or AWSClients.get_s3_client()

    @retry(max_attempts=3, logger=logger)
    def get_object(self, bucket: str, key: str) -> dict[str, Any]:
        """Retrieve an object from S3 with retry logic"""
        try:
            logger.info(json.dumps({"action": "get_object", "bucket": bucket, "key": key}))
            response = self._s3_client.get_object(Bucket=bucket, Key=key)
            return response
        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "get_object_error",
                        "bucket": bucket,
                        "key": key,
                        "error": str(e),
                    }
                )
            )
            raise S3Error(
                f"Failed to get object from S3: {e!s}", original_exception=e, bucket=bucket, key=key
            )

    def get_object_stream(self, bucket: str, key: str, chunk_size: int = 1024 * 1024):
        """Get an S3 object as a stream of chunks to handle large files efficiently"""
        try:
            response = self._s3_client.get_object(Bucket=bucket, Key=key)
            stream = response["Body"]

            # Return iterator of chunks
            return stream.iter_chunks(chunk_size=chunk_size)

        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "get_object_stream_error",
                        "bucket": bucket,
                        "key": key,
                        "error": str(e),
                    }
                )
            )
            raise S3Error(
                f"Failed to stream object from S3: {e!s}",
                original_exception=e,
                bucket=bucket,
                key=key,
            )


class APIClient:
    """Client for calling external APIs
    In a real implementation, this would make actual API calls
    """

    def __init__(self, base_url: str | None = None, api_key: str | None = None, timeout: int = 30):
        """Initialize API client with configuration"""
        self.base_url = base_url
        self.api_key = api_key
        self.timeout = timeout
        # Create circuit breaker for API calls
        self.circuit_breaker = CircuitBreaker(
            name="api-service", failure_threshold=5, reset_timeout=60, logger=logger
        )

    @retry(max_attempts=3, backoff_factor=2, logger=logger)
    def call_api(self, endpoint: str, data: dict[str, Any]) -> dict[str, Any]:
        """Call API endpoint with retry and circuit breaker"""

        def _make_api_call():
            # Simulate API processing time (5-30 seconds)
            process_time = random.uniform(5, 30)
            time.sleep(process_time)

            # Simulate occasional API errors (5% chance)
            if random.random() < 0.05:
                logger.error(
                    json.dumps(
                        {
                            "action": "api_call_error",
                            "endpoint": endpoint,
                            "error": "API timeout",
                            "dt.metrics": {"api_call_error": 1, "api_call_duration": process_time},
                        }
                    )
                )
                # Some errors should not be retried (example: invalid auth)
                retry_allowed = random.random() < 0.8
                raise APIError(
                    "API call timed out",
                    status_code=500 if retry_allowed else 401,
                    retry_allowed=retry_allowed,
                )

            # Simulate successful API response
            result = {
                "status": "success",
                "processing_time": process_time,
                "result_id": f"res-{random.randint(1000, 9999)}",
                "timestamp": time.time(),
                "data": data,
            }

            logger.info(
                json.dumps(
                    {
                        "action": "api_call_complete",
                        "endpoint": endpoint,
                        "process_time": process_time,
                        "dt.metrics": {"api_call_success": 1, "api_call_duration": process_time},
                    }
                )
            )

            return result

        # Log API call start
        logger.info(
            json.dumps(
                {
                    "action": "api_call_start",
                    "endpoint": endpoint,
                    "dt.metrics": {"api_call_count": 1, "api_call_start": time.time()},
                }
            )
        )

        # Execute with circuit breaker
        try:
            return self.circuit_breaker.execute(_make_api_call)
        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "api_call_error",
                        "endpoint": endpoint,
                        "error": str(e),
                        "dt.metrics": {"api_call_error": 1},
                    }
                )
            )
            raise

    def process_batch(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Process multiple items in a single API call to improve throughput"""
        if not items:
            return []

        batch_endpoint = "batch-process"

        try:
            # Use circuit breaker and retry via call_api method
            result = self.call_api(batch_endpoint, {"items": items})

            # In a real implementation, process the response
            # For now, we'll simulate a successful batch response
            return [
                {
                    "item_id": i,
                    "original_data": item,
                    "result": f"batch-processed-{random.randint(1000, 9999)}",
                    "success": True,
                }
                for i, item in enumerate(items)
            ]
        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "batch_process_error",
                        "items_count": len(items),
                        "error": str(e),
                        "dt.metrics": {"batch_process_error": 1},
                    }
                )
            )
            raise APIError(
                f"Failed to process batch of {len(items)} items: {e!s}", original_exception=e
            )
