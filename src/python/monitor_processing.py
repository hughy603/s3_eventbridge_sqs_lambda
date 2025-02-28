#!/usr/bin/env python3
"""Script to monitor the processing status of the S3 objects.
This includes checking SQS queue depth, Step Functions executions, and Lambda invocations.
"""

import argparse
import json
import logging
import time
from datetime import datetime, timedelta

import boto3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def get_queue_attributes(queue_url: str) -> dict:
    """Get attributes for the SQS queue.

    Args:
        queue_url: URL of the SQS queue

    Returns:
        Dictionary of queue attributes
    """
    sqs = boto3.client("sqs")
    response = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=[
            "ApproximateNumberOfMessages",
            "ApproximateNumberOfMessagesNotVisible",
            "ApproximateNumberOfMessagesDelayed",
        ],
    )
    return response["Attributes"]


def get_step_functions_executions(state_machine_arn: str) -> list:
    """Get recent executions of the Step Functions state machine.

    Args:
        state_machine_arn: ARN of the Step Functions state machine

    Returns:
        List of recent executions
    """
    sfn = boto3.client("stepfunctions")
    response = sfn.list_executions(
        stateMachineArn=state_machine_arn,
        maxResults=20,
    )
    return response["executions"]


def get_lambda_metrics(function_name: str) -> dict:
    """Get invocation metrics for the Lambda function.

    Args:
        function_name: Name of the Lambda function

    Returns:
        Dictionary of invocation metrics
    """
    cloudwatch = boto3.client("cloudwatch")
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)

    metrics = {}

    # Get invocation count
    invocation_response = cloudwatch.get_metric_statistics(
        Namespace="AWS/Lambda",
        MetricName="Invocations",
        Dimensions=[{"Name": "FunctionName", "Value": function_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,  # 5 minutes
        Statistics=["Sum"],
    )
    metrics["invocations"] = sum(point["Sum"] for point in invocation_response["Datapoints"])

    # Get error count
    error_response = cloudwatch.get_metric_statistics(
        Namespace="AWS/Lambda",
        MetricName="Errors",
        Dimensions=[{"Name": "FunctionName", "Value": function_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,  # 5 minutes
        Statistics=["Sum"],
    )
    metrics["errors"] = sum(point["Sum"] for point in error_response["Datapoints"])

    # Get duration
    duration_response = cloudwatch.get_metric_statistics(
        Namespace="AWS/Lambda",
        MetricName="Duration",
        Dimensions=[{"Name": "FunctionName", "Value": function_name}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,  # 5 minutes
        Statistics=["Average", "Maximum"],
    )
    if duration_response["Datapoints"]:
        metrics["avg_duration"] = max(point["Average"] for point in duration_response["Datapoints"])
        metrics["max_duration"] = max(point["Maximum"] for point in duration_response["Datapoints"])
    else:
        metrics["avg_duration"] = 0
        metrics["max_duration"] = 0

    return metrics


def monitor(
    queue_url: str,
    state_machine_arn: str,
    function_name: str,
    interval: int = 30,
    count: int = 10,
) -> None:
    """Monitor the processing status of the S3 objects.

    Args:
        queue_url: URL of the SQS queue
        state_machine_arn: ARN of the Step Functions state machine
        function_name: Name of the Lambda function
        interval: Interval between checks in seconds
        count: Number of checks to perform
    """
    for i in range(count):
        logger.info(f"Check {i + 1}/{count}")

        # Check SQS queue
        queue_attrs = get_queue_attributes(queue_url)
        logger.info(
            f"SQS Queue: {queue_attrs['ApproximateNumberOfMessages']} messages, "
            f"{queue_attrs['ApproximateNumberOfMessagesNotVisible']} in flight, "
            f"{queue_attrs['ApproximateNumberOfMessagesDelayed']} delayed"
        )

        # Check Step Functions executions
        executions = get_step_functions_executions(state_machine_arn)
        running = sum(1 for e in executions if e["status"] == "RUNNING")
        succeeded = sum(1 for e in executions if e["status"] == "SUCCEEDED")
        failed = sum(1 for e in executions if e["status"] == "FAILED")
        logger.info(
            f"Step Functions: {running} running, {succeeded} succeeded, {failed} failed "
            f"(out of {len(executions)} recent executions)"
        )

        # Check Lambda invocations
        lambda_metrics = get_lambda_metrics(function_name)
        logger.info(
            f"Lambda: {lambda_metrics['invocations']} invocations, "
            f"{lambda_metrics['errors']} errors, "
            f"avg: {lambda_metrics['avg_duration']:.2f}ms, "
            f"max: {lambda_metrics['max_duration']:.2f}ms"
        )

        logger.info("-" * 80)

        if i < count - 1:
            time.sleep(interval)


def main():
    """Parse command-line arguments and run the monitoring."""
    parser = argparse.ArgumentParser(description="Monitor the processing status of S3 objects")
    parser.add_argument("--queue", required=True, help="URL of the SQS queue")
    parser.add_argument(
        "--state-machine", required=True, help="ARN of the Step Functions state machine"
    )
    parser.add_argument("--function", required=True, help="Name of the Lambda function")
    parser.add_argument(
        "--interval", type=int, default=30, help="Interval between checks in seconds (default: 30)"
    )
    parser.add_argument(
        "--count", type=int, default=10, help="Number of checks to perform (default: 10)"
    )

    args = parser.parse_args()

    monitor(
        args.queue,
        args.state_machine,
        args.function,
        args.interval,
        args.count,
    )


if __name__ == "__main__":
    main()
