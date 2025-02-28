"""Tests for the simulate_uploads script."""

import json
import os

# Import the script
import sys
import tempfile
from unittest.mock import MagicMock, patch

import boto3
import pytest
from botocore.exceptions import ClientError
from moto import mock_s3

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from simulate_uploads import S3Error, S3Uploader, UploadConfig, UploadSimulator, main, parse_args


@pytest.fixture
def s3_bucket():
    """Create a mock S3 bucket for testing."""
    with mock_s3():
        s3 = boto3.client("s3", region_name="us-east-1")
        bucket_name = "test-bucket"
        s3.create_bucket(Bucket=bucket_name)
        yield bucket_name


@pytest.fixture
def mock_s3_client():
    """Create a mock S3 client."""
    client = MagicMock()
    client.upload_file = MagicMock()
    client.put_object_tagging = MagicMock()
    return client


@pytest.fixture
def upload_config():
    """Create a test upload configuration."""
    return UploadConfig(
        bucket_name="test-bucket",
        key_prefix="test-uploads",
        rows_per_file=5,
        num_files=3,
        max_workers=2,
    )


class TestS3Uploader:
    """Tests for the S3Uploader class."""

    def test_init_with_region(self):
        """Test initialization with region."""
        with patch("boto3.client") as mock_boto:
            uploader = S3Uploader(aws_region="us-west-2")
            mock_boto.assert_called_once_with("s3", region_name="us-west-2")

    def test_init_with_env_var(self):
        """Test initialization with environment variable."""
        with patch.dict(os.environ, {"AWS_REGION": "us-east-1"}):
            with patch("boto3.client") as mock_boto:
                uploader = S3Uploader()
                mock_boto.assert_called_once_with("s3", region_name="us-east-1")

    def test_init_with_client(self):
        """Test initialization with client."""
        mock_client = MagicMock()
        uploader = S3Uploader(s3_client=mock_client)
        assert uploader.s3_client == mock_client

    def test_generate_test_data(self):
        """Test data generation."""
        uploader = S3Uploader(s3_client=MagicMock())
        data = uploader.generate_test_data(num_rows=5)

        assert len(data) == 5
        for row in data:
            assert "id" in row
            assert "value" in row
            assert "timestamp" in row

    def test_write_csv_to_s3_success(self, mock_s3_client):
        """Test successful CSV upload to S3."""
        uploader = S3Uploader(s3_client=mock_s3_client)

        # Test data
        data = [
            {"id": "1", "value": "100", "timestamp": "1234567890"},
            {"id": "2", "value": "200", "timestamp": "1234567891"},
        ]

        # Call the method with a patched tempfile
        with patch("tempfile.NamedTemporaryFile") as mock_temp:
            mock_file = MagicMock()
            mock_temp.return_value.__enter__.return_value = mock_file
            mock_file.name = "/tmp/test.csv"

            key = uploader.write_csv_to_s3("test-bucket", "test-prefix", data)

            # Verify the S3 client calls
            mock_s3_client.upload_file.assert_called_once()
            mock_s3_client.put_object_tagging.assert_called_once()

            # Verify the key format
            assert key.startswith("test-prefix/")
            assert key.endswith(".csv")

    def test_write_csv_to_s3_empty_data(self, mock_s3_client):
        """Test handling of empty data."""
        uploader = S3Uploader(s3_client=mock_s3_client)
        key = uploader.write_csv_to_s3("test-bucket", "test-prefix", [])

        assert key is None
        mock_s3_client.upload_file.assert_not_called()

    def test_write_csv_to_s3_s3_error(self, mock_s3_client):
        """Test handling of S3 client error."""
        uploader = S3Uploader(s3_client=mock_s3_client)
        data = [{"id": "1", "value": "100", "timestamp": "1234567890"}]

        # Simulate an S3 client error
        error_response = {"Error": {"Code": "AccessDenied", "Message": "Access Denied"}}
        mock_s3_client.upload_file.side_effect = ClientError(error_response, "PutObject")

        with patch("tempfile.NamedTemporaryFile") as mock_temp:
            mock_file = MagicMock()
            mock_temp.return_value.__enter__.return_value = mock_file
            mock_file.name = "/tmp/test.csv"

            with pytest.raises(S3Error) as excinfo:
                uploader.write_csv_to_s3("test-bucket", "test-prefix", data)

            assert "Error uploading to S3" in str(excinfo.value)
            assert "Access Denied" in str(excinfo.value)

    def test_upload_file_worker_success(self):
        """Test successful worker execution."""
        # Create a mock uploader where all methods are mocked
        uploader = S3Uploader(s3_client=MagicMock())
        uploader.generate_test_data = MagicMock(return_value=[{"id": "1"}])
        uploader.write_csv_to_s3 = MagicMock(return_value="test-key.csv")

        # Test config
        config = {"bucket_name": "test-bucket", "key_prefix": "test-prefix", "rows_per_file": 5}

        # Test with mocked sleep
        with patch("time.sleep"):
            key = uploader.upload_file_worker(config)

            # Verify method calls
            uploader.generate_test_data.assert_called_once_with(5)
            uploader.write_csv_to_s3.assert_called_once_with(
                "test-bucket", "test-prefix", [{"id": "1"}]
            )

            assert key == "test-key.csv"

    def test_upload_file_worker_error(self):
        """Test worker error handling."""
        # Create a mock uploader with an error in write_csv_to_s3
        uploader = S3Uploader(s3_client=MagicMock())
        uploader.generate_test_data = MagicMock(return_value=[{"id": "1"}])
        uploader.write_csv_to_s3 = MagicMock(side_effect=S3Error("Test error"))

        # Test config
        config = {"bucket_name": "test-bucket", "key_prefix": "test-prefix", "rows_per_file": 5}

        # Test with mocked sleep
        with patch("time.sleep"):
            key = uploader.upload_file_worker(config)

            # Verify the error was handled
            assert key is None


class TestUploadSimulator:
    """Tests for the UploadSimulator class."""

    def test_simulate_uploads_success(self, upload_config):
        """Test successful simulation."""
        # Create a mock uploader
        mock_uploader = MagicMock()
        mock_uploader.upload_file_worker.side_effect = ["key1.csv", "key2.csv", "key3.csv"]

        # Create the simulator
        simulator = UploadSimulator(mock_uploader)

        # Run the simulation
        keys = simulator.simulate_uploads(upload_config)

        # Verify uploader calls and results
        assert mock_uploader.upload_file_worker.call_count == 3
        assert len(keys) == 3
        assert "key1.csv" in keys
        assert "key2.csv" in keys
        assert "key3.csv" in keys

    def test_simulate_uploads_partial_failures(self, upload_config):
        """Test simulation with some failures."""
        # Create a mock uploader with one failure
        mock_uploader = MagicMock()
        mock_uploader.upload_file_worker.side_effect = [
            "key1.csv",
            None,  # Simulated failure
            "key3.csv",
        ]

        # Create the simulator
        simulator = UploadSimulator(mock_uploader)

        # Run the simulation
        keys = simulator.simulate_uploads(upload_config)

        # Verify uploader calls and results
        assert mock_uploader.upload_file_worker.call_count == 3
        assert len(keys) == 2
        assert "key1.csv" in keys
        assert "key3.csv" in keys

    def test_simulate_uploads_worker_exceptions(self, upload_config):
        """Test simulation with exceptions."""
        # Create a mock uploader with one exception
        mock_uploader = MagicMock()
        mock_uploader.upload_file_worker.side_effect = [
            "key1.csv",
            Exception("Test exception"),
            "key3.csv",
        ]

        # Create the simulator
        simulator = UploadSimulator(mock_uploader)

        # Run the simulation with patched concurrent.futures
        with patch("concurrent.futures.ThreadPoolExecutor") as mock_executor:
            # Setup the mock
            mock_instance = MagicMock()
            mock_executor.return_value.__enter__.return_value = mock_instance

            # Setup future results
            future1, future2, future3 = MagicMock(), MagicMock(), MagicMock()
            future1.result.return_value = "key1.csv"
            future2.result.side_effect = Exception("Test exception")
            future3.result.return_value = "key3.csv"

            # Make as_completed return our futures
            with patch("concurrent.futures.as_completed", return_value=[future1, future2, future3]):
                keys = simulator.simulate_uploads(upload_config)

                # Verify results
                assert len(keys) == 2
                assert "key1.csv" in keys
                assert "key3.csv" in keys

    def test_simulate_uploads_with_output_file(self, upload_config):
        """Test simulation with output file."""
        # Create a mock uploader
        mock_uploader = MagicMock()
        mock_uploader.upload_file_worker.side_effect = ["key1.csv", "key2.csv", "key3.csv"]

        # Create the simulator
        simulator = UploadSimulator(mock_uploader)

        # Create a temporary output file
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            try:
                # Update config to use the temporary file
                upload_config.output_file = tmp.name

                # Run the simulation
                keys = simulator.simulate_uploads(upload_config)

                # Verify the output file
                with open(tmp.name) as f:
                    output = json.load(f)
                    assert output == keys
                    assert len(output) == 3

            finally:
                # Clean up the temporary file
                if os.path.exists(tmp.name):
                    os.remove(tmp.name)


def test_parse_args():
    """Test argument parsing."""
    # Test with minimal arguments
    with patch("sys.argv", ["simulate_uploads.py", "--bucket", "test-bucket"]):
        config = parse_args()
        assert config.bucket_name == "test-bucket"
        assert config.key_prefix == "uploads"  # default
        assert config.rows_per_file == 50  # default
        assert config.num_files == 100  # default
        assert config.max_workers == 10  # default
        assert config.output_file is None

    # Test with all arguments
    with patch(
        "sys.argv",
        [
            "simulate_uploads.py",
            "--bucket",
            "test-bucket",
            "--files",
            "10",
            "--rows",
            "20",
            "--workers",
            "5",
            "--prefix",
            "custom-prefix",
            "--output",
            "output.json",
            "--region",
            "us-west-2",
        ],
    ):
        config = parse_args()
        assert config.bucket_name == "test-bucket"
        assert config.key_prefix == "custom-prefix"
        assert config.rows_per_file == 20
        assert config.num_files == 10
        assert config.max_workers == 5
        assert config.output_file == "output.json"
        assert config.aws_region == "us-west-2"


def test_main_success():
    """Test successful main execution."""
    # Mock dependencies
    mock_config = MagicMock()
    mock_simulator = MagicMock()
    mock_uploader = MagicMock()

    # Set up patches
    with patch("simulate_uploads.parse_args", return_value=mock_config):
        with patch("simulate_uploads.S3Uploader", return_value=mock_uploader):
            with patch("simulate_uploads.UploadSimulator", return_value=mock_simulator):
                # Run main
                result = main()

                # Verify calls
                mock_simulator.simulate_uploads.assert_called_once_with(mock_config)
                assert result == 0


def test_main_error():
    """Test main error handling."""
    # Mock dependencies to raise an exception
    with patch("simulate_uploads.parse_args", side_effect=Exception("Test error")):
        # Run main
        result = main()

        # Verify error handling
        assert result == 1


def test_integration_with_moto(s3_bucket):
    """Test integration with moto."""
    # Create a minimal config
    config = UploadConfig(bucket_name=s3_bucket, num_files=2, rows_per_file=2, max_workers=1)

    # Create real objects with mocked sleep
    with patch("time.sleep"):
        uploader = S3Uploader()
        simulator = UploadSimulator(uploader)

        # Run the simulation
        keys = simulator.simulate_uploads(config)

        # Verify results
        assert len(keys) == 2

        # Check that files were actually created in S3
        s3 = boto3.client("s3", region_name="us-east-1")
        for key in keys:
            response = s3.get_object(Bucket=s3_bucket, Key=key)
            content = response["Body"].read().decode("utf-8")

            # Verify it's a valid CSV
            assert "id,value,timestamp" in content
            assert len(content.splitlines()) == 3  # header + 2 rows
