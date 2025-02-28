#!/usr/bin/env python3
"""Performance test script for the S3 event processor.
Tests processing performance in different modes:
- Sequential processing (baseline)
- Batch processing
- Async processing
"""

import argparse
import csv
import io
import json
import logging
import os
import random
import string
import time
from typing import Dict, List

import boto3
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from functions.aws_clients import AWSClients
from functions.processors import CSVProcessor, S3ObjectProcessor

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def generate_csv_data(rows: int, columns: int = 5) -> str:
    """Generate random CSV data with specified number of rows and columns"""
    buffer = io.StringIO()
    writer = csv.writer(buffer)

    # Generate column headers
    headers = [f"column_{i}" for i in range(columns)]
    writer.writerow(headers)

    # Generate data rows
    for _ in range(rows):
        row = [
            "".join(random.choices(string.ascii_letters + string.digits, k=10))
            for _ in range(columns)
        ]
        writer.writerow(row)

    return buffer.getvalue()


def upload_test_files(
    bucket_name: str,
    file_count: int,
    rows_per_file: int,
    columns: int = 5,
    prefix: str = "perf-test/",
) -> list[str]:
    """Upload test files to S3 bucket and return the list of keys"""
    s3_client = AWSClients.get_s3_client()
    keys = []

    for i in range(file_count):
        # Generate random CSV data
        csv_data = generate_csv_data(rows_per_file, columns)
        key = f"{prefix}test_file_{i}.csv"

        # Upload to S3
        s3_client.put_object(Bucket=bucket_name, Key=key, Body=csv_data)
        keys.append(key)

    return keys


def run_performance_test(
    bucket_name: str,
    file_keys: list[str],
    test_sequential: bool = True,
    test_batch: bool = True,
    test_async: bool = True,
    repetitions: int = 3,
) -> dict:
    """Run performance tests using different processing methods
    Returns timing results for each method
    """
    results = {"sequential": [], "batch": [], "async": []}

    s3_client = boto3.client("s3")
    processor = S3ObjectProcessor()

    for key in file_keys:
        file_results = {"key": key}

        # Test sequential processing
        if test_sequential:
            seq_times = []
            for _ in range(repetitions):
                start_time = time.time()
                processor.process(bucket_name, key, use_async=False, use_batch=False)
                duration = time.time() - start_time
                seq_times.append(duration)
            file_results["sequential"] = {
                "mean": np.mean(seq_times),
                "min": np.min(seq_times),
                "max": np.max(seq_times),
                "std": np.std(seq_times),
                "all_times": seq_times,
            }

        # Test batch processing
        if test_batch:
            batch_times = []
            for _ in range(repetitions):
                start_time = time.time()
                processor.process(bucket_name, key, use_async=False, use_batch=True)
                duration = time.time() - start_time
                batch_times.append(duration)
            file_results["batch"] = {
                "mean": np.mean(batch_times),
                "min": np.min(batch_times),
                "max": np.max(batch_times),
                "std": np.std(batch_times),
                "all_times": batch_times,
            }

        # Test async processing
        if test_async:
            async_times = []
            for _ in range(repetitions):
                start_time = time.time()
                processor.process(bucket_name, key, use_async=True, use_batch=False)
                duration = time.time() - start_time
                async_times.append(duration)
            file_results["async"] = {
                "mean": np.mean(async_times),
                "min": np.min(async_times),
                "max": np.max(async_times),
                "std": np.std(async_times),
                "all_times": async_times,
            }

        results[key] = file_results

    return results


def generate_report(results: dict, output_dir: str = "results"):
    """Generate performance report with charts"""
    os.makedirs(output_dir, exist_ok=True)

    # Create DataFrames for analysis
    rows = []
    for key, file_results in results.items():
        if key in ("sequential", "batch", "async"):
            continue

        row = {"file": key}

        if "sequential" in file_results:
            row["sequential_mean"] = file_results["sequential"]["mean"]
            row["sequential_min"] = file_results["sequential"]["min"]
            row["sequential_max"] = file_results["sequential"]["max"]

        if "batch" in file_results:
            row["batch_mean"] = file_results["batch"]["mean"]
            row["batch_min"] = file_results["batch"]["min"]
            row["batch_max"] = file_results["batch"]["max"]

        if "async" in file_results:
            row["async_mean"] = file_results["async"]["mean"]
            row["async_min"] = file_results["async"]["min"]
            row["async_max"] = file_results["async"]["max"]

        rows.append(row)

    df = pd.DataFrame(rows)

    # Save raw data
    df.to_csv(f"{output_dir}/performance_results.csv", index=False)

    # Generate summary report
    with open(f"{output_dir}/performance_summary.txt", "w") as f:
        f.write("Performance Test Summary\n")
        f.write("=======================\n\n")

        # Overall statistics
        f.write("Overall Statistics:\n")
        if "sequential_mean" in df.columns:
            f.write(
                f"Sequential Processing: {df['sequential_mean'].mean():.2f}s (± {df['sequential_mean'].std():.2f}s)\n"
            )
        if "batch_mean" in df.columns:
            f.write(
                f"Batch Processing: {df['batch_mean'].mean():.2f}s (± {df['batch_mean'].std():.2f}s)\n"
            )
        if "async_mean" in df.columns:
            f.write(
                f"Async Processing: {df['async_mean'].mean():.2f}s (± {df['async_mean'].std():.2f}s)\n"
            )

        # Speedup calculations
        f.write("\nSpeedup Ratios:\n")
        if "sequential_mean" in df.columns and "batch_mean" in df.columns:
            batch_speedup = df["sequential_mean"].mean() / df["batch_mean"].mean()
            f.write(f"Batch vs. Sequential: {batch_speedup:.2f}x\n")

        if "sequential_mean" in df.columns and "async_mean" in df.columns:
            async_speedup = df["sequential_mean"].mean() / df["async_mean"].mean()
            f.write(f"Async vs. Sequential: {async_speedup:.2f}x\n")

        if "batch_mean" in df.columns and "async_mean" in df.columns:
            batch_async_ratio = df["batch_mean"].mean() / df["async_mean"].mean()
            f.write(f"Async vs. Batch: {batch_async_ratio:.2f}x\n")

    # Generate charts
    plt.figure(figsize=(10, 6))

    methods = []
    means = []
    errors = []

    if "sequential_mean" in df.columns:
        methods.append("Sequential")
        means.append(df["sequential_mean"].mean())
        errors.append(df["sequential_mean"].std())

    if "batch_mean" in df.columns:
        methods.append("Batch")
        means.append(df["batch_mean"].mean())
        errors.append(df["batch_mean"].std())

    if "async_mean" in df.columns:
        methods.append("Async")
        means.append(df["async_mean"].mean())
        errors.append(df["async_mean"].std())

    plt.bar(methods, means, yerr=errors, alpha=0.7, capsize=10)
    plt.ylabel("Average Processing Time (s)")
    plt.title("Performance Comparison of Processing Methods")
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.savefig(f"{output_dir}/performance_comparison.png", dpi=300, bbox_inches="tight")

    logger.info(f"Performance report generated in {output_dir} directory")


def ensure_bucket_exists(bucket_name: str, region: str = "us-east-1") -> bool:
    """Ensure the S3 bucket exists, create if it doesn't"""
    s3_client = boto3.client("s3", region_name=region)

    try:
        s3_client.head_bucket(Bucket=bucket_name)
        return True
    except Exception:
        # Bucket doesn't exist, create it
        try:
            if region == "us-east-1":
                s3_client.create_bucket(Bucket=bucket_name)
            else:
                s3_client.create_bucket(
                    Bucket=bucket_name, CreateBucketConfiguration={"LocationConstraint": region}
                )
            return True
        except Exception as e:
            logger.error(f"Failed to create bucket: {e}")
            return False


def main():
    """Main entry point for the performance test script"""
    parser = argparse.ArgumentParser(description="Performance test for S3 event processor")
    parser.add_argument("--bucket", required=True, help="S3 bucket name for testing")
    parser.add_argument("--files", type=int, default=5, help="Number of test files to create")
    parser.add_argument("--rows", type=int, default=100, help="Number of rows per test file")
    parser.add_argument("--columns", type=int, default=5, help="Number of columns per test file")
    parser.add_argument("--sequential", action="store_true", help="Test sequential processing")
    parser.add_argument("--batch", action="store_true", help="Test batch processing")
    parser.add_argument("--async_", action="store_true", help="Test async processing")
    parser.add_argument("--all", action="store_true", help="Test all processing methods")
    parser.add_argument("--reps", type=int, default=3, help="Number of repetitions per test")
    parser.add_argument("--output", default="results", help="Output directory for results")
    parser.add_argument("--region", default="us-east-1", help="AWS region to use")

    args = parser.parse_args()

    # If no specific methods are selected, use --all
    if not (args.sequential or args.batch or args.async_):
        args.all = True

    # Ensure the bucket exists
    if not ensure_bucket_exists(args.bucket, args.region):
        logger.error(f"Failed to ensure bucket {args.bucket} exists")
        return

    # Upload test files
    logger.info(f"Uploading {args.files} test files with {args.rows} rows each")
    keys = upload_test_files(
        bucket_name=args.bucket,
        file_count=args.files,
        rows_per_file=args.rows,
        columns=args.columns,
    )

    # Run performance tests
    logger.info("Running performance tests")
    results = run_performance_test(
        bucket_name=args.bucket,
        file_keys=keys,
        test_sequential=args.sequential or args.all,
        test_batch=args.batch or args.all,
        test_async=args.async_ or args.all,
        repetitions=args.reps,
    )

    # Generate report
    logger.info("Generating performance report")
    generate_report(results, args.output)

    logger.info("Performance testing complete")


if __name__ == "__main__":
    main()
