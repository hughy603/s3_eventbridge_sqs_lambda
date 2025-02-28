"""Pytest configuration for the tests."""

import os
import sys

import boto3
import pytest
from moto import mock_s3, mock_sqs

# Add the functions directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions"))


@pytest.fixture(scope="function")
def aws_credentials():
    """Mocked AWS Credentials for boto3"""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"


@pytest.fixture(scope="function")
def s3(aws_credentials):
    """Mock S3 service"""
    with mock_s3():
        yield boto3.client("s3", region_name="us-east-1")


@pytest.fixture(scope="function")
def sqs(aws_credentials):
    """Mock SQS service"""
    with mock_sqs():
        yield boto3.client("sqs", region_name="us-east-1")
