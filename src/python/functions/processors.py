"""Processor classes for handling S3 object processing"""

import asyncio
import csv
import io
import json
import logging
import time
from typing import Any, Dict, List, Optional

from .clients import APIClient, S3Client
from .errors import ProcessingError
from .utils import log_safe_object, parse_csv_stream

logger = logging.getLogger(__name__)


class CSVProcessor:
    """Processes CSV data from S3 objects"""

    def __init__(self, api_client: APIClient | None = None):
        """Initialize with optional API client for dependency injection"""
        self.api_client = api_client or APIClient()

    def calculate_optimal_batch_size(
        self, content_size: int, object_key: str, priority: str = "standard"
    ) -> int:
        """Calculate optimal batch size based on content size and priority

        Args:
            content_size: Size of the content in bytes
            object_key: S3 object key (used to determine file type)
            priority: Priority level ("high", "standard", "low")

        Returns:
            Optimal batch size for processing
        """
        # Base batch sizes per priority
        base_sizes = {
            "high": 25,  # Process high priority items in smaller batches for faster start
            "standard": 50,  # Default batch size
            "low": 100,  # Process low priority items in larger batches for efficiency
        }

        # Get base size for priority (default to standard if invalid)
        base_size = base_sizes.get(priority, base_sizes["standard"])

        # File type adjustments
        if object_key.endswith(".csv"):
            # CSV files are typically row-based and process efficiently
            file_type_factor = 1.5
        elif any(object_key.endswith(ext) for ext in [".json", ".xml"]):
            # Structured data may be more complex to process
            file_type_factor = 0.8
        else:
            # Default for unknown file types
            file_type_factor = 1.0

        # Size adjustments - scale batch size with file size
        if content_size > 100 * 1024 * 1024:  # > 100MB
            size_factor = 2.0  # Very large files get larger batches
        elif content_size > 10 * 1024 * 1024:  # > 10MB
            size_factor = 1.5  # Large files get somewhat larger batches
        elif content_size < 1024 * 1024:  # < 1MB
            size_factor = 0.5  # Small files get smaller batches
        else:
            size_factor = 1.0  # Medium files use the base size

        # Calculate final batch size and ensure it's at least 10 and at most 500
        optimal_batch_size = max(10, min(500, int(base_size * file_type_factor * size_factor)))

        logger.info(
            json.dumps(
                {
                    "action": "calculate_batch_size",
                    "content_size_bytes": content_size,
                    "file_type": object_key.split(".")[-1] if "." in object_key else "unknown",
                    "priority": priority,
                    "optimal_batch_size": optimal_batch_size,
                }
            )
        )

        return optimal_batch_size

    def process_content(
        self,
        content: str,
        bucket: str = "",
        key: str = "",
        batch_size: int | None = None,
        priority: str = "standard",
    ) -> list[dict[str, Any]]:
        """Process CSV content from the S3 object
        Processes rows in batches with adaptive sizing for better performance

        Args:
            content: The CSV content to process
            bucket: S3 bucket (for logging)
            key: S3 object key (for batch size calculation and logging)
            batch_size: Optional fixed batch size (if None, calculates optimal size)
            priority: Processing priority ("high", "standard", "low")
        """
        try:
            start_time = time.time()
            content_size = len(content.encode("utf-8"))

            # Calculate optimal batch size if not provided
            if batch_size is None:
                batch_size = self.calculate_optimal_batch_size(content_size, key, priority)

            logger.info(
                json.dumps(
                    {
                        "action": "process_csv_content",
                        "bucket": bucket,
                        "key": key,
                        "content_size_bytes": content_size,
                        "batch_size": batch_size,
                        "priority": priority,
                    }
                )
            )

            results = []
            batch_count = 0
            total_rows = 0

            # Parse CSV data in chunks
            for chunk in parse_csv_stream(content, chunk_size=batch_size):
                batch_count += 1
                total_rows += len(chunk)

                # Process this batch of rows
                batch_start = time.time()
                batch_results = self.api_client.process_batch(chunk)
                batch_duration = time.time() - batch_start

                # Log batch processing stats
                logger.info(
                    json.dumps(
                        {
                            "action": "batch_processed",
                            "batch_number": batch_count,
                            "batch_size": len(chunk),
                            "batch_duration": batch_duration,
                            "rows_per_second": len(chunk) / max(0.001, batch_duration),
                            "dt.metrics": {
                                "batch_processing_time": batch_duration,
                                "rows_processed": len(chunk),
                            },
                        }
                    )
                )

                results.extend(batch_results)

                # Adaptive batch size adjustment for subsequent batches
                # If the batch took too long, reduce the batch size
                if batch_duration > 10 and batch_size > 20:
                    new_batch_size = max(10, int(batch_size * 0.8))
                    logger.info(
                        json.dumps(
                            {
                                "action": "batch_size_adjustment",
                                "reason": "slow_processing",
                                "old_batch_size": batch_size,
                                "new_batch_size": new_batch_size,
                            }
                        )
                    )
                    batch_size = new_batch_size
                # If the batch was processed very quickly, increase the batch size
                elif batch_duration < 1 and batch_size < 500:
                    new_batch_size = min(500, int(batch_size * 1.2))
                    logger.info(
                        json.dumps(
                            {
                                "action": "batch_size_adjustment",
                                "reason": "fast_processing",
                                "old_batch_size": batch_size,
                                "new_batch_size": new_batch_size,
                            }
                        )
                    )
                    batch_size = new_batch_size

            # Log overall processing stats
            processing_time = time.time() - start_time
            logger.info(
                json.dumps(
                    {
                        "action": "process_csv_complete",
                        "total_batches": batch_count,
                        "total_rows": total_rows,
                        "total_processing_time": processing_time,
                        "rows_per_second": total_rows / max(0.001, processing_time),
                        "dt.metrics": {
                            "csv_processing_time": processing_time,
                            "total_batches": batch_count,
                            "total_rows": total_rows,
                        },
                    }
                )
            )

            return results

        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "process_csv_content_error",
                        "error": str(e),
                        "bucket": bucket,
                        "key": key,
                    }
                )
            )
            raise ProcessingError(f"Failed to process CSV content: {e!s}")

    async def process_content_async(self, content: str) -> list[dict[str, Any]]:
        """Process CSV content asynchronously for better performance"""
        try:
            logger.info(json.dumps({"action": "process_csv_content_async"}))

            # Parse the CSV
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)

            if not rows:
                logger.warning(
                    json.dumps({"action": "process_csv_content", "status": "empty_file"})
                )
                return []

            # Process rows in parallel
            tasks = []
            for row in rows:
                # In a real implementation, this would use aiohttp or similar for async API calls
                # Since we're simulating, we'll use asyncio.to_thread to make it non-blocking
                tasks.append(asyncio.to_thread(self._process_row, row))

            # Wait for all tasks to complete
            results = await asyncio.gather(*tasks, return_exceptions=True)

            # Handle any exceptions
            processed_results = []
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    logger.error(
                        json.dumps(
                            {"action": "process_row_error", "row_index": i, "error": str(result)}
                        )
                    )
                else:
                    processed_results.append(result)

            return processed_results

        except Exception as e:
            logger.error(json.dumps({"action": "process_csv_content_async_error", "error": str(e)}))
            raise ProcessingError(f"Failed to process CSV content asynchronously: {e!s}")

    def _process_row(self, row_data: dict[str, str]) -> dict[str, Any]:
        """Process a single row of data (for async processing)"""
        try:
            # Log with sensitive data redacted
            logger.info(
                json.dumps({"action": "process_row", "row_data": log_safe_object(row_data)})
            )

            # Call API for this row
            result = self.api_client.call_api("process-row", row_data)

            return {"data": row_data, "api_result": result}
        except Exception as e:
            logger.error(
                json.dumps(
                    {
                        "action": "process_row_error",
                        "row_data": log_safe_object(row_data),
                        "error": str(e),
                    }
                )
            )
            raise


class S3ObjectProcessor:
    """Processes objects from S3 buckets"""

    def __init__(
        self, s3_client: S3Client | None = None, csv_processor: CSVProcessor | None = None
    ):
        """Initialize the processor with optional clients for dependency injection"""
        self.s3_client = s3_client or S3Client()
        self.csv_processor = csv_processor or CSVProcessor()

    def process(
        self,
        bucket: str,
        key: str,
        use_async: bool = False,
        use_batch: bool = True,
        priority: str = "standard",
        batch_size: int | None = None,
        chunked_processing: bool = False,
    ) -> dict[str, Any]:
        """Process an object from S3"""
        start_time = time.time()
        logger.info(
            json.dumps(
                {
                    "action": "process_start",
                    "bucket": bucket,
                    "key": key,
                    "dt.metrics": {"process_start": 1},
                }
            )
        )

        try:
            # Handle large files with chunked processing if requested
            if chunked_processing and key.endswith(".csv"):
                logger.info(
                    json.dumps({"action": "chunked_processing", "bucket": bucket, "key": key})
                )
                # Get the object size to determine if we need streaming
                response = self.s3_client.get_object(bucket, key)
                content_length = int(response.get("ContentLength", 0))

                if content_length > 50 * 1024 * 1024:  # > 50MB
                    # Process in chunks
                    results = []
                    chunk_streams = self.s3_client.get_object_stream(bucket, key)
                    buffer = b""

                    for chunk in chunk_streams:
                        buffer += chunk
                        # Once we have enough data, process it
                        if len(buffer) > 5 * 1024 * 1024:  # Process in 5MB chunks
                            chunk_content = buffer.decode("utf-8", errors="replace")
                            chunk_results = self.csv_processor.process_content(
                                chunk_content,
                                bucket=bucket,
                                key=key,
                                batch_size=batch_size,
                                priority=priority,
                            )
                            results.extend(chunk_results)
                            buffer = b""

                    # Process any remaining data
                    if buffer:
                        chunk_content = buffer.decode("utf-8", errors="replace")
                        chunk_results = self.csv_processor.process_content(
                            chunk_content,
                            bucket=bucket,
                            key=key,
                            batch_size=batch_size,
                            priority=priority,
                        )
                        results.extend(chunk_results)
                else:
                    # File is not large enough to warrant chunked processing
                    content = response["Body"].read().decode("utf-8")
                    results = self.csv_processor.process_content(
                        content, bucket=bucket, key=key, batch_size=batch_size, priority=priority
                    )
            else:
                # Regular processing for normal sized files
                response = self.s3_client.get_object(bucket, key)
                content = response["Body"].read().decode("utf-8")

                # Process the CSV content
                if use_async:
                    # For async processing (non-blocking)
                    loop = asyncio.get_event_loop()
                    results = loop.run_until_complete(
                        self.csv_processor.process_content_async(content)
                    )
                elif use_batch:
                    # For batch processing with adaptive sizing
                    results = self.csv_processor.process_content(
                        content, bucket=bucket, key=key, batch_size=batch_size, priority=priority
                    )
                else:
                    # Legacy sequential processing method
                    csv_reader = csv.DictReader(io.StringIO(content))
                    rows = list(csv_reader)
                    results = []

                    for row in rows:
                        api_result = self.csv_processor._process_row(row)
                        results.append(api_result)

            processing_time = time.time() - start_time
            logger.info(
                json.dumps(
                    {
                        "action": "process_complete",
                        "bucket": bucket,
                        "key": key,
                        "rows_processed": len(results),
                        "processing_time": processing_time,
                        "processing_mode": (
                            "chunked"
                            if chunked_processing
                            else "async"
                            if use_async
                            else "adaptive_batch"
                            if use_batch and batch_size is None
                            else "fixed_batch"
                            if use_batch
                            else "sequential"
                        ),
                        "priority": priority,
                        "batch_size": batch_size,
                        "rows_per_second": len(results) / max(0.001, processing_time),
                        "dt.metrics": {
                            "process_success": 1,
                            "process_duration": processing_time,
                            "rows_processed": len(results),
                            "rows_per_second": len(results) / max(0.001, processing_time),
                        },
                    }
                )
            )

            return {
                "statusCode": 200,
                "body": {
                    "bucket": bucket,
                    "key": key,
                    "rows_processed": len(results),
                    "processing_time": processing_time,
                    "processing_mode": (
                        "chunked"
                        if chunked_processing
                        else "async"
                        if use_async
                        else "adaptive_batch"
                        if use_batch and batch_size is None
                        else "fixed_batch"
                        if use_batch
                        else "sequential"
                    ),
                    "priority": priority,
                    "rows_per_second": len(results) / max(0.001, processing_time),
                    "results": results,
                },
            }
        except Exception as e:
            processing_time = time.time() - start_time
            logger.error(
                json.dumps(
                    {
                        "action": "process_error",
                        "bucket": bucket,
                        "key": key,
                        "error": str(e),
                        "processing_time": processing_time,
                        "dt.metrics": {"process_error": 1, "process_duration": processing_time},
                    }
                )
            )

            # Reraise the exception to trigger Lambda retry mechanism
            raise
