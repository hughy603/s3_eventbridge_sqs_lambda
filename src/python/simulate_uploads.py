#!/usr/bin/env python3
"""Script to simulate a large number of objects being written to S3 in parallel.
This is used to test the staggered Lambda invocation solution.
"""

import argparse
import concurrent.futures
import csv
import json
import logging
import os
import random
import tempfile
import time
import uuid
from dataclasses import dataclass
from typing import Dict, List, Optional

import boto3
from botocore.exceptions import ClientError


# Configure logging with environment variables
def setup_logging() -> logging.Logger:
    """Set up logging configuration from environment variables."""
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    log_format = os.environ.get(
        "LOG_FORMAT", "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    logger = logging.getLogger(__name__)
    logger.setLevel(log_level)

    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter(log_format)
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    return logger


logger = setup_logging()


@dataclass
class UploadConfig:
    """Configuration for S3 uploads."""

    bucket_name: str
    key_prefix: str = "uploads"
    rows_per_file: int = 50
    num_files: int = 100
    max_workers: int = 10
    output_file: str | None = None
    aws_region: str | None = None


class S3Error(Exception):
    """Exception for S3-related errors."""

    pass


class S3Uploader:
    """Class for handling S3 upload operations."""

    def __init__(self, aws_region: str | None = None, s3_client=None):
        """Initialize S3 uploader.

        Args:
            aws_region: AWS region to use
            s3_client: Optional boto3 S3 client (primarily for testing)
        """
        self.s3_client = s3_client or boto3.client(
            "s3", region_name=aws_region or os.environ.get("AWS_REGION")
        )

    def generate_test_data(self, num_rows: int = 100) -> list[dict[str, str]]:
        """Generate test data with random values.

        Args:
            num_rows: Number of rows to generate

        Returns:
            List of dictionaries containing test data
        """
        data = []
        for _ in range(num_rows):
            data.append(
                {
                    "id": str(uuid.uuid4()),
                    "value": str(random.randint(1, 1000)),
                    "timestamp": str(int(time.time())),
                }
            )
        return data

    def write_csv_to_s3(
        self, bucket_name: str, key_prefix: str, data: list[dict[str, str]]
    ) -> str | None:
        """Write data to a CSV file and upload to S3.

        Args:
            bucket_name: S3 bucket name
            key_prefix: Prefix for the S3 key
            data: List of dictionaries to write to CSV

        Returns:
            S3 key of the uploaded file or None if data is empty

        Raises:
            S3Error: If S3 operation fails
        """
        if not data:
            logger.warning("No data provided for CSV generation")
            return None

        # Generate a unique key
        key = f"{key_prefix}/{uuid.uuid4()}.csv"
        tmp_filename = None

        try:
            # Create a temporary file with secure permissions
            with tempfile.NamedTemporaryFile(mode="w+", delete=False, suffix=".csv") as csvfile:
                tmp_filename = csvfile.name

                # Write CSV data
                fieldnames = data[0].keys()
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(data)

            # Upload to S3
            try:
                self.s3_client.upload_file(tmp_filename, bucket_name, key)
                logger.info(f"Uploaded file to s3://{bucket_name}/{key}")

                # Add metadata to help with tracking
                self.s3_client.put_object_tagging(
                    Bucket=bucket_name,
                    Key=key,
                    Tagging={
                        "TagSet": [
                            {"Key": "UploadTimestamp", "Value": str(int(time.time()))},
                            {"Key": "RecordCount", "Value": str(len(data))},
                            {"Key": "Source", "Value": "simulation"},
                        ]
                    },
                )

                return key

            except ClientError as e:
                error_code = e.response.get("Error", {}).get("Code", "Unknown")
                error_message = e.response.get("Error", {}).get("Message", str(e))
                logger.error(f"S3 error: {error_message} (Code: {error_code})")
                raise S3Error(f"Error uploading to S3: {error_message}")

            except Exception as e:
                logger.error(f"Unexpected error uploading to S3: {e!s}")
                raise S3Error(f"Unexpected error uploading to S3: {e!s}")

        finally:
            # Clean up temporary file
            if tmp_filename and os.path.exists(tmp_filename):
                os.remove(tmp_filename)

    def upload_file_worker(self, config: dict) -> str | None:
        """Worker function to generate data and upload to S3.

        Args:
            config: Dictionary containing configuration for the worker

        Returns:
            S3 key of the uploaded file or None on failure
        """
        bucket_name = config["bucket_name"]
        key_prefix = config["key_prefix"]
        rows_per_file = config["rows_per_file"]

        try:
            # Add randomness to simulate real-world scenario
            time.sleep(random.uniform(0.1, 1.0))

            # Generate random data
            data = self.generate_test_data(rows_per_file)

            # Upload to S3
            return self.write_csv_to_s3(bucket_name, key_prefix, data)

        except Exception as e:
            logger.error(f"Worker error: {e!s}")
            return None


class UploadSimulator:
    """Class to simulate multiple parallel uploads to S3."""

    def __init__(self, uploader: S3Uploader):
        """Initialize simulator.

        Args:
            uploader: S3Uploader instance
        """
        self.uploader = uploader

    def simulate_uploads(self, config: UploadConfig) -> list[str]:
        """Simulate uploading multiple files to S3 in parallel.

        Args:
            config: Upload configuration

        Returns:
            List of S3 keys that were uploaded
        """
        logger.info(
            f"Simulating upload of {config.num_files} files with {config.rows_per_file} rows each "
            f"to bucket {config.bucket_name} using {config.max_workers} workers"
        )

        start_time = time.time()
        uploaded_keys = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=config.max_workers) as executor:
            args_list = [
                {
                    "bucket_name": config.bucket_name,
                    "key_prefix": config.key_prefix,
                    "rows_per_file": config.rows_per_file,
                }
                for _ in range(config.num_files)
            ]

            future_to_args = {
                executor.submit(self.uploader.upload_file_worker, args): args for args in args_list
            }

            for future in concurrent.futures.as_completed(future_to_args):
                try:
                    key = future.result()
                    if key:
                        uploaded_keys.append(key)
                except Exception as e:
                    logger.error(f"Thread execution error: {e!s}")

        elapsed_time = time.time() - start_time
        upload_rate = len(uploaded_keys) / elapsed_time if elapsed_time > 0 else 0

        logger.info(
            f"Uploaded {len(uploaded_keys)} files in {elapsed_time:.2f} seconds "
            f"({upload_rate:.2f} files/second)"
        )

        if config.output_file:
            with open(config.output_file, "w") as f:
                json.dump(uploaded_keys, f, indent=2)
            logger.info(f"Wrote list of {len(uploaded_keys)} keys to {config.output_file}")

        return uploaded_keys


def parse_args() -> UploadConfig:
    """Parse command-line arguments.

    Returns:
        UploadConfig object
    """
    parser = argparse.ArgumentParser(
        description="Simulate uploading multiple files to S3 in parallel"
    )
    parser.add_argument("--bucket", required=True, help="S3 bucket name to upload files to")
    parser.add_argument(
        "--files", type=int, default=100, help="Number of files to upload (default: 100)"
    )
    parser.add_argument(
        "--rows", type=int, default=50, help="Number of rows per file (default: 50)"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=10,
        help="Maximum number of concurrent workers (default: 10)",
    )
    parser.add_argument(
        "--prefix",
        default="uploads",
        help="Prefix for the S3 keys (default: 'uploads')",
    )
    parser.add_argument(
        "--output",
        help="Output file to write the list of uploaded keys (optional)",
    )
    parser.add_argument(
        "--region",
        help="AWS region (defaults to AWS_REGION environment variable)",
    )

    args = parser.parse_args()

    return UploadConfig(
        bucket_name=args.bucket,
        key_prefix=args.prefix,
        rows_per_file=args.rows,
        num_files=args.files,
        max_workers=args.workers,
        output_file=args.output,
        aws_region=args.region,
    )


def main():
    """Parse command-line arguments and run the simulation."""
    try:
        config = parse_args()
        uploader = S3Uploader(aws_region=config.aws_region)
        simulator = UploadSimulator(uploader)
        simulator.simulate_uploads(config)
    except Exception as e:
        logger.error(f"Error running simulation: {e!s}")
        return 1
    return 0


if __name__ == "__main__":
    exit(main())
