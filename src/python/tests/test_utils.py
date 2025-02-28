"""Tests for utility functions"""

import time
from unittest import mock

import pytest
from functions.errors import APIError, CircuitBreakerOpenError, ValidationError
from functions.utils import (
    CircuitBreaker,
    log_safe_object,
    parse_csv_stream,
    retry,
    validate_s3_details,
)


class TestValidation:
    """Tests for validation utilities"""

    def test_validate_s3_details(self):
        """Test S3 details validation"""
        # Valid case
        validate_s3_details({"bucket": "test-bucket", "key": "test/file.csv"})

        # Invalid cases
        with pytest.raises(ValidationError):
            validate_s3_details({})

        with pytest.raises(ValidationError):
            validate_s3_details({"bucket": "test-bucket"})

        with pytest.raises(ValidationError):
            validate_s3_details({"key": "test/file.csv"})

        with pytest.raises(ValidationError):
            validate_s3_details({"bucket": "test-bucket", "key": "../path-traversal"})


class TestSafeLogging:
    """Tests for safe logging utilities"""

    def test_log_safe_object(self):
        """Test sensitive data masking"""
        # Test simple object
        test_obj = {"username": "user1", "password": "secret123", "data": "public info"}

        safe_obj = log_safe_object(test_obj)
        assert safe_obj["username"] == "user1"
        assert safe_obj["password"] == "***REDACTED***"
        assert safe_obj["data"] == "public info"

        # Test nested objects
        nested_obj = {
            "user": {
                "name": "user1",
                "credentials": {"password": "secret123", "api_key": "key123"},
            },
            "data": "public info",
        }

        safe_nested = log_safe_object(nested_obj)
        assert safe_nested["user"]["name"] == "user1"
        assert safe_nested["user"]["credentials"]["password"] == "***REDACTED***"
        assert safe_nested["user"]["credentials"]["api_key"] == "***REDACTED***"
        assert safe_nested["data"] == "public info"

        # Test with arrays
        array_obj = {
            "users": [
                {"name": "user1", "password": "secret1"},
                {"name": "user2", "password": "secret2"},
            ]
        }

        safe_array = log_safe_object(array_obj)
        assert safe_array["users"][0]["name"] == "user1"
        assert safe_array["users"][0]["password"] == "***REDACTED***"
        assert safe_array["users"][1]["name"] == "user2"
        assert safe_array["users"][1]["password"] == "***REDACTED***"

        # Test with custom sensitive fields
        custom_obj = {
            "username": "user1",
            "ssn": "123-45-6789",
            "credit_card": "4111-1111-1111-1111",
        }

        safe_custom = log_safe_object(custom_obj, sensitive_fields={"ssn", "credit_card"})
        assert safe_custom["username"] == "user1"
        assert safe_custom["ssn"] == "***REDACTED***"
        assert safe_custom["credit_card"] == "***REDACTED***"


class TestRetry:
    """Tests for retry decorator"""

    def test_retry_success_first_attempt(self):
        """Test successful function on first attempt"""
        mock_func = mock.Mock(return_value="success")
        decorated = retry()(mock_func)

        result = decorated()
        assert result == "success"
        assert mock_func.call_count == 1

    def test_retry_success_second_attempt(self):
        """Test successful function on second attempt"""
        mock_func = mock.Mock(side_effect=[APIError("Timeout"), "success"])
        decorated = retry(max_attempts=3)(mock_func)

        result = decorated()
        assert result == "success"
        assert mock_func.call_count == 2

    def test_retry_all_fails(self):
        """Test function that fails all retry attempts"""
        error = APIError("Persistent failure")
        mock_func = mock.Mock(side_effect=[error, error, error])
        decorated = retry(max_attempts=3)(mock_func)

        with pytest.raises(APIError):
            decorated()

        assert mock_func.call_count == 3

    def test_retry_non_retryable_exception(self):
        """Test exception that shouldn't be retried"""
        # Create a non-retryable error
        error = APIError("Auth failure", retry_allowed=False)
        mock_func = mock.Mock(side_effect=[error])
        decorated = retry(max_attempts=3)(mock_func)

        with pytest.raises(APIError):
            decorated()

        # Should only be called once since retry_allowed is False
        assert mock_func.call_count == 1


class TestCircuitBreaker:
    """Tests for circuit breaker pattern"""

    def test_circuit_breaker_success(self):
        """Test successful execution with circuit breaker"""
        cb = CircuitBreaker(name="test", failure_threshold=2)
        mock_func = mock.Mock(return_value="success")

        result = cb.execute(mock_func, "arg1", kwarg1="value1")
        assert result == "success"
        mock_func.assert_called_once_with("arg1", kwarg1="value1")
        assert cb.state == "CLOSED"

    def test_circuit_breaker_opens_after_failures(self):
        """Test circuit opens after threshold failures"""
        cb = CircuitBreaker(name="test", failure_threshold=2)
        mock_func = mock.Mock(side_effect=Exception("test error"))

        # First failure
        with pytest.raises(Exception):
            cb.execute(mock_func)
        assert cb.state == "CLOSED"
        assert cb.failure_count == 1

        # Second failure should open the circuit
        with pytest.raises(Exception):
            cb.execute(mock_func)
        assert cb.state == "OPEN"
        assert cb.failure_count == 2

        # Next call should be rejected with circuit open
        with pytest.raises(CircuitBreakerOpenError):
            cb.execute(mock_func)

    def test_circuit_breaker_half_open_after_timeout(self):
        """Test circuit goes to half-open state after timeout"""
        cb = CircuitBreaker(name="test", failure_threshold=2, reset_timeout=0.1)
        mock_func = mock.Mock(
            side_effect=[Exception("first error"), Exception("second error"), "success"]
        )

        # First two calls fail and open circuit
        with pytest.raises(Exception):
            cb.execute(mock_func)
        with pytest.raises(Exception):
            cb.execute(mock_func)
        assert cb.state == "OPEN"

        # Wait for reset timeout
        time.sleep(0.2)

        # Next call should succeed and close the circuit
        result = cb.execute(mock_func)
        assert result == "success"
        assert cb.state == "CLOSED"
        assert cb.failure_count == 0


class TestCSVParsing:
    """Tests for CSV parsing utilities"""

    def test_parse_csv_stream(self):
        """Test CSV stream parsing"""
        # Test CSV content
        csv_content = "name,value\ntest1,100\ntest2,200\ntest3,300"

        # Parse with default chunk size
        chunks = list(parse_csv_stream(csv_content, chunk_size=2))

        # Should have 2 chunks (2 rows in first, 1 in second)
        assert len(chunks) == 2
        assert len(chunks[0]) == 2
        assert len(chunks[1]) == 1

        # Verify data
        assert chunks[0][0]["name"] == "test1"
        assert chunks[0][0]["value"] == "100"
        assert chunks[0][1]["name"] == "test2"
        assert chunks[0][1]["value"] == "200"
        assert chunks[1][0]["name"] == "test3"
        assert chunks[1][0]["value"] == "300"

        # Test with larger chunk size
        large_chunks = list(parse_csv_stream(csv_content, chunk_size=10))
        assert len(large_chunks) == 1
        assert len(large_chunks[0]) == 3
