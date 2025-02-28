"""Error types for the application"""

from typing import Optional


class ProcessingError(Exception):
    """Base exception for processing errors"""

    def __init__(self, message: str, original_exception: Exception | None = None):
        super().__init__(message)
        self.original_exception = original_exception


class S3Error(ProcessingError):
    """Exception raised for S3-related errors"""

    def __init__(
        self,
        message: str,
        original_exception: Exception | None = None,
        bucket: str | None = None,
        key: str | None = None,
    ):
        super().__init__(message, original_exception)
        self.bucket = bucket
        self.key = key


class APIError(ProcessingError):
    """Exception raised for API-related errors"""

    def __init__(
        self,
        message: str,
        original_exception: Exception | None = None,
        status_code: int | None = None,
        retry_allowed: bool = True,
    ):
        super().__init__(message, original_exception)
        self.status_code = status_code
        self.retry_allowed = retry_allowed


class ValidationError(ProcessingError):
    """Exception raised for validation errors"""

    def __init__(
        self, message: str, original_exception: Exception | None = None, field: str | None = None
    ):
        super().__init__(message, original_exception)
        self.field = field


class CircuitBreakerOpenError(ProcessingError):
    """Exception raised when a circuit breaker is open"""

    def __init__(self, message: str, service: str | None = None, reset_time: float | None = None):
        super().__init__(message)
        self.service = service
        self.reset_time = reset_time


class ConfigurationError(ProcessingError):
    """Exception raised for configuration errors"""

    pass
