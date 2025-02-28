"""Tests for the process_object Lambda function"""

import json
import os
import unittest
from unittest import mock

import boto3
import pytest
from botocore.stub import Stubber
from functions.aws_clients import AWSClients
from functions.clients import APIClient, S3Client
from functions.errors import APIError, S3Error, ValidationError
from functions.process_object import lambda_handler
from functions.processors import CSVProcessor, S3ObjectProcessor
from functions.utils import validate_s3_details
from moto import mock_s3


@pytest.fixture
def s3_client():
    """Create a mocked S3 client"""
    with mock_s3():
        s3_client = boto3.client("s3", region_name="us-east-1")
        yield s3_client


@pytest.fixture
def s3_bucket(s3_client):
    """Create a test bucket and add a test file"""
    bucket_name = "test-bucket"
    s3_client.create_bucket(Bucket=bucket_name)

    # Create a test CSV file
    csv_content = "name,value\ntest1,100\ntest2,200\ntest3,300"
    s3_client.put_object(Bucket=bucket_name, Key="test/file.csv", Body=csv_content)

    return bucket_name


class TestProcessObject:
    """Tests for the process_object module"""

    def test_validation(self):
        """Test input validation"""
        # Missing bucket
        with pytest.raises(ValidationError):
            validate_s3_details({"key": "some-key"})

        # Missing key
        with pytest.raises(ValidationError):
            validate_s3_details({"bucket": "some-bucket"})

        # Path traversal attempt
        with pytest.raises(ValidationError):
            validate_s3_details({"bucket": "test-bucket", "key": "../dangerous/path"})

        # Invalid bucket name
        with pytest.raises(ValidationError):
            validate_s3_details({"bucket": "INVALID_UPPER", "key": "test.csv"})

        # Valid input
        assert validate_s3_details({"bucket": "test-bucket", "key": "test/file.csv"}) is None

    def test_s3_client(self):
        """Test S3Client functionality"""
        # Mock S3 client
        mock_boto3_client = mock.MagicMock()
        mock_get_object = mock.MagicMock()
        mock_get_object.return_value = {"Body": mock.MagicMock()}
        mock_boto3_client.get_object = mock_get_object

        # Create S3Client with mocked boto3 client
        s3_client = S3Client(s3_client=mock_boto3_client)

        # Test get_object
        s3_client.get_object("test-bucket", "test/file.csv")
        mock_get_object.assert_called_once_with(Bucket="test-bucket", Key="test/file.csv")

        # Test error handling
        mock_get_object.side_effect = Exception("S3 error")
        with pytest.raises(S3Error):
            s3_client.get_object("test-bucket", "test/file.csv")

    def test_api_client(self):
        """Test APIClient functionality"""
        # Create API client with circuit breaker
        api_client = APIClient()

        # Mock the circuit breaker execute method
        api_client.circuit_breaker.execute = mock.MagicMock()
        api_client.circuit_breaker.execute.return_value = {
            "status": "success",
            "result_id": "test-123",
        }

        # Test call_api
        result = api_client.call_api("test-endpoint", {"test": "data"})
        assert result["status"] == "success"

        # Test error handling
        api_client.circuit_breaker.execute.side_effect = APIError("API error")
        with pytest.raises(APIError):
            api_client.call_api("test-endpoint", {"test": "data"})

    @mock.patch("functions.clients.S3Client.get_object")
    @mock.patch("functions.clients.APIClient.call_api")
    def test_csv_processor(self, mock_call_api, mock_get_object):
        """Test CSVProcessor functionality"""
        # Setup mock responses
        mock_call_api.return_value = {"status": "success", "result_id": "test-123"}

        # Create processor
        api_client = APIClient()
        api_client.call_api = mock_call_api
        csv_processor = CSVProcessor(api_client=api_client)

        # Test processing a csv
        csv_content = "name,value\ntest1,100\ntest2,200\ntest3,300"
        results = csv_processor.process_content(csv_content)

        # Verify API was called for batch processing
        assert mock_call_api.called

        # Verify results
        assert len(results) > 0

    @mock.patch("functions.processors.S3ObjectProcessor.process")
    def test_lambda_handler_success(self, mock_process):
        """Test successful lambda handler execution"""
        # Setup mock response
        mock_process.return_value = {
            "statusCode": 200,
            "body": {"bucket": "test-bucket", "key": "test/file.csv", "rows_processed": 3},
        }

        # Call lambda handler
        event = {"s3_details": {"bucket": "test-bucket", "key": "test/file.csv"}}
        result = lambda_handler(event, None)

        # Verify result
        assert result["statusCode"] == 200
        assert result["body"]["bucket"] == "test-bucket"
        assert result["body"]["key"] == "test/file.csv"

    def test_lambda_handler_validation_error(self):
        """Test lambda handler with validation error"""
        # Call lambda handler with invalid input
        event = {
            "s3_details": {
                "key": "test/file.csv"
                # Missing bucket
            }
        }
        result = lambda_handler(event, None)

        # Verify error response
        assert result["statusCode"] == 400
        assert "Validation error" in result["body"]

    @mock.patch("functions.processors.S3ObjectProcessor.process")
    def test_lambda_handler_processing_error(self, mock_process):
        """Test lambda handler with processing error"""
        # Setup mock to raise exception
        mock_process.side_effect = Exception("Processing error")

        # Call lambda handler
        event = {"s3_details": {"bucket": "test-bucket", "key": "test/file.csv"}}
        result = lambda_handler(event, None)

        # Verify error response
        assert result["statusCode"] == 500
        assert "Error processing S3 object" in result["body"]

    def test_integration(self, s3_bucket):
        """Integration test with mocked S3"""
        # Reset AWS clients to use moto mock
        AWSClients.reset_clients()

        # Call lambda handler
        event = {
            "s3_details": {"bucket": s3_bucket, "key": "test/file.csv"},
            "processing_options": {
                "use_async": False,  # Avoid asyncio in tests
                "use_batch": True,
            },
        }

        # Mock the API client to avoid real API calls
        with mock.patch("src.python.functions.clients.APIClient.call_api") as mock_call_api:
            # Setup API mock
            mock_call_api.return_value = {"status": "success", "result_id": "test-123"}

            # Call lambda handler
            result = lambda_handler(event, None)

            # Verify result
            assert result["statusCode"] == 200
            assert result["body"]["bucket"] == s3_bucket
            assert result["body"]["key"] == "test/file.csv"
            assert result["body"]["rows_processed"] == 3
