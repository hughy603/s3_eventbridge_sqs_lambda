"""AWS client utilities providing connection pooling and reuse"""

import boto3
from botocore.config import Config


class AWSClients:
    """Singleton class for AWS clients to enable connection pooling
    and reduce the overhead of creating new connections.
    """

    _s3_client = None
    _sqs_client = None
    _step_functions_client = None
    _lambda_client = None

    @classmethod
    def get_s3_client(cls, region_name=None):
        """Get or create an S3 client"""
        if cls._s3_client is None:
            config = Config(
                retries={"max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=60
            )
            cls._s3_client = boto3.client("s3", region_name=region_name, config=config)
        return cls._s3_client

    @classmethod
    def get_sqs_client(cls, region_name=None):
        """Get or create an SQS client"""
        if cls._sqs_client is None:
            config = Config(
                retries={"max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=60
            )
            cls._sqs_client = boto3.client("sqs", region_name=region_name, config=config)
        return cls._sqs_client

    @classmethod
    def get_step_functions_client(cls, region_name=None):
        """Get or create a Step Functions client"""
        if cls._step_functions_client is None:
            config = Config(
                retries={"max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=60
            )
            cls._step_functions_client = boto3.client(
                "stepfunctions", region_name=region_name, config=config
            )
        return cls._step_functions_client

    @classmethod
    def get_lambda_client(cls, region_name=None):
        """Get or create a Lambda client"""
        if cls._lambda_client is None:
            config = Config(
                retries={"max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=60
            )
            cls._lambda_client = boto3.client("lambda", region_name=region_name, config=config)
        return cls._lambda_client

    @classmethod
    def reset_clients(cls):
        """Reset all clients - mainly for testing"""
        cls._s3_client = None
        cls._sqs_client = None
        cls._step_functions_client = None
        cls._lambda_client = None
