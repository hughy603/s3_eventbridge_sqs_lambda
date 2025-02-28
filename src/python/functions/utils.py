"""Utility functions for the processor"""

import csv
import functools
import io
import json
import logging
import re
import time
from collections.abc import Callable
from typing import Any, Dict, List, Optional, Set

from .errors import APIError, CircuitBreakerOpenError, ValidationError


def validate_s3_details(s3_details: dict[str, str]) -> None:
    """Validate S3 details to prevent security issues
    Raises ValidationError if invalid
    """
    if not s3_details:
        raise ValidationError("S3 details are missing")

    bucket = s3_details.get("bucket")
    key = s3_details.get("key")

    if not bucket:
        raise ValidationError("Bucket name is missing", field="bucket")

    if not key:
        raise ValidationError("Object key is missing", field="key")

    # Check for path traversal attempts
    if ".." in key or key.startswith("/"):
        raise ValidationError("Invalid object key: potential path traversal", field="key")

    # Validate bucket name format (simplified check)
    if not re.match(r"^[a-z0-9][-a-z0-9.]{1,61}[a-z0-9]$", bucket):
        raise ValidationError(f"Invalid bucket name format: {bucket}", field="bucket")


def log_safe_object(
    obj: dict[str, Any], sensitive_fields: set[str] | None = None
) -> dict[str, Any]:
    """Create a copy of an object with sensitive fields masked for safe logging"""
    if sensitive_fields is None:
        sensitive_fields = {"password", "ssn", "credit_card", "secret", "token", "key"}

    if not isinstance(obj, dict):
        return obj

    safe_obj = {}
    for key, value in obj.items():
        if any(sensitive_name in key.lower() for sensitive_name in sensitive_fields):
            safe_obj[key] = "***REDACTED***"
        elif isinstance(value, dict):
            safe_obj[key] = log_safe_object(value, sensitive_fields)
        elif isinstance(value, list):
            safe_obj[key] = [
                log_safe_object(item, sensitive_fields) if isinstance(item, dict) else item
                for item in value
            ]
        else:
            safe_obj[key] = value

    return safe_obj


def retry(
    max_attempts: int = 3,
    backoff_factor: float = 1.5,
    retry_exceptions: tuple = (APIError,),
    logger: logging.Logger | None = None,
):
    """Retry decorator with exponential backoff"""

    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_exception = None

            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except retry_exceptions as e:
                    last_exception = e

                    # Check if retry is allowed
                    if hasattr(e, "retry_allowed") and not e.retry_allowed:
                        if logger:
                            logger.warning(f"Retry not allowed for error: {e!s}, giving up.")
                        raise

                    # Skip retry on last attempt
                    if attempt == max_attempts - 1:
                        break

                    wait_time = backoff_factor**attempt
                    if logger:
                        logger.info(
                            f"Retrying after error: {e!s}, "
                            f"attempt {attempt + 1}/{max_attempts}, "
                            f"waiting {wait_time:.2f}s"
                        )
                    time.sleep(wait_time)

            if last_exception:
                raise last_exception

        return wrapper

    return decorator


class CircuitBreaker:
    """Circuit breaker implementation to prevent continued calls to failing services"""

    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        reset_timeout: int = 60,
        logger: logging.Logger | None = None,
    ):
        self.name = name
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.reset_timeout = reset_timeout
        self.state = "CLOSED"  # CLOSED, OPEN, HALF-OPEN
        self.last_failure_time = 0
        self.logger = logger

    def execute(self, func: Callable, *args, **kwargs):
        """Execute a function with circuit breaker protection"""
        if self.state == "OPEN":
            elapsed = time.time() - self.last_failure_time
            if elapsed > self.reset_timeout:
                if self.logger:
                    self.logger.info(f"Circuit {self.name} entering half-open state")
                self.state = "HALF-OPEN"
            else:
                if self.logger:
                    self.logger.warning(f"Circuit {self.name} is open, request rejected")
                raise CircuitBreakerOpenError(
                    f"Circuit breaker '{self.name}' is open",
                    service=self.name,
                    reset_time=self.last_failure_time + self.reset_timeout,
                )

        try:
            result = func(*args, **kwargs)

            # Reset on success in half-open state
            if self.state == "HALF-OPEN":
                if self.logger:
                    self.logger.info(f"Circuit {self.name} closing after successful request")
                self.state = "CLOSED"
                self.failure_count = 0

            return result

        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()

            if self.state != "OPEN" and self.failure_count >= self.failure_threshold:
                if self.logger:
                    self.logger.warning(
                        f"Circuit {self.name} opening after {self.failure_count} failures"
                    )
                self.state = "OPEN"

            raise e


def parse_csv_stream(csv_stream, chunk_size: int = 100) -> list[dict[str, str]]:
    """Parse CSV data in chunks to avoid loading entire file into memory
    Returns a generator that yields chunks of parsed rows
    """
    reader = csv.DictReader(io.StringIO(csv_stream))
    rows = []

    for row in reader:
        rows.append(row)
        if len(rows) >= chunk_size:
            yield rows
            rows = []

    if rows:
        yield rows
