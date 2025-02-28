# S3 EventBridge SQS Lambda

A production-ready, reusable pattern for staggered processing of S3 events with built-in reliability, monitoring, and observability features.

## Overview

This application demonstrates a battle-tested architecture for reliable, controlled processing of S3 object events. It prevents overwhelming downstream systems by controlling Lambda concurrency through a staggered invocation pattern.

### Key Features

- **Reliable Event Processing**: Guaranteed at-least-once delivery with DLQs at every stage
- **Controlled Concurrency**: Staggered Lambda invocation prevents overwhelming backend services
- **Comprehensive Monitoring**: Complete observability with Dynatrace (metrics) and Splunk (logs)
- **Auto-scaling**: Lambda concurrency scales based on SQS queue depth
- **Reusable Pattern**: Terraform modules enable easy application to any S3-triggered Lambda use case
- **Performance Testing**: Built-in tools to test and measure system performance

### Technology Stack

- **Infrastructure**: Terraform modules with AWS best practices
- **Application**: Python 3.13 with modular, testable architecture
- **CI/CD**: Pre-commit hooks with ruff linting and formatting
- **Monitoring**: Dynatrace for metrics, Splunk for logs

This application implements the following requirements:

1. Pre-commit hooks for Terraform & Python validation (using ruff)
2. Test application to simulate parallel S3 object uploads
3. S3 event to SQS queue routing through EventBridge
4. Staggered Lambda invocations via Step Functions
5. Lambda processing of S3 objects with simulated API calls
6. 90%+ unit test coverage
7. Pre-commit validation for code quality
8. Comprehensive documentation
9. DLQs for guaranteed at-least-once delivery
10. CloudWatch alerts for system health monitoring
11. DynaTrace dashboard with CloudWatch monitoring
12. Central SMTP server for email notifications
13. Auto-scaling Lambda concurrency based on queue depth
14. Performance testing with metrics collection
15. Industry-standard DLQ redriving practices
16. Mermaid architecture diagrams
17. Event-driven error alerting
18. Dynatrace integration for serverless monitoring
19. Splunk integration for Lambda logs
20. Dynatrace as primary metrics monitoring tool
21. Splunk as primary log monitoring tool
22. Reusable Terraform modules for the pattern

## Architecture

View the detailed interactive architecture diagram (created with Mermaid):
- [Architecture Diagram](docs/architecture.md)

1. Objects are uploaded to S3 in parallel
2. S3 PutObject events are sent to EventBridge
3. EventBridge rules route events to SQS for buffering
4. DLQs ensure at-least-once delivery at every step in the process
5. Step Functions consumes messages from SQS and invokes Lambda functions in a staggered manner
6. Lambda processes each object (reads CSV file and calls simulated API for each row)
7. CloudWatch alarms monitor the health of every component in the pipeline
8. DynaTrace dashboard provides application performance monitoring
9. Auto-scaling adjusts Lambda concurrency based on queue depth

## Components

- **S3**: Stores CSV files
- **EventBridge**: Routes S3 events to SQS
- **SQS**: Buffers events to handle traffic spikes with DLQ support
- **Step Functions**: Orchestrates staggered Lambda invocations
- **Lambda**: Processes each object with DLQ for failed processing
- **CloudWatch Alarms**: Monitor the health of the pipeline components
- **DynaTrace**: Application Performance Monitoring dashboard
- **Auto-Scaling**: Adjusts Lambda concurrency based on queue depth
- **Performance Testing**: Scripts to measure and collect system metrics

## Getting Started

### Prerequisites

- Python 3.13
- Poetry (Python dependency management)
- Terraform 1.0.0+ with AWS provider ~> 5.0
- AWS CLI configured with appropriate credentials
- Pre-commit for code validation
- Dynatrace account (for metric monitoring)
- Splunk instance (for log analysis)

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/s3_eventbridge_sqs_lambda.git
   cd s3_eventbridge_sqs_lambda
   ```

2. Install Poetry (if not already installed):
   ```bash
   curl -sSL https://install.python-poetry.org | python3 -
   ```

3. Install dependencies with Poetry:
   ```bash
   poetry install
   ```

4. Install pre-commit hooks:
   ```bash
   poetry run pre-commit install
   ```

5. Initialize Terraform:
   ```bash
   cd src/terraform
   terraform init
   ```

6. Configure your AWS credentials:
   ```bash
   aws configure
   # Or set environment variables:
   # export AWS_ACCESS_KEY_ID="your-access-key"
   # export AWS_SECRET_ACCESS_KEY="your-secret-key"
   # export AWS_DEFAULT_REGION="your-region"
   ```

### Deploying Infrastructure

```bash
cd src/terraform
terraform init
terraform plan
terraform apply
```

### Running the Simulation

The simulation script uploads multiple CSV files to S3 in parallel:

```bash
poetry run python src/python/simulate_uploads.py --bucket <bucket-name> --files 100 --rows 50 --workers 10
```

Or use the Makefile:

```bash
make simulate BUCKET=<bucket-name> FILES=100 ROWS=50 WORKERS=10
```

### Monitoring Processing

Use the monitoring script to check processing status:

```bash
poetry run python src/python/monitor_processing.py --queue <queue-url> --state-machine <state-machine-arn> --function <function-name>
```

Or use the Makefile:

```bash
make monitor QUEUE=<queue-url> STATE_MACHINE=<state-machine-arn> FUNCTION=<function-name>
```

### Performance Testing

Run the performance test script to measure system performance:

```bash
poetry run python src/python/performance_test.py --bucket <bucket-name> --queue <queue-url> --state-machine <state-machine-arn> --function <function-name>
```

Or use the Makefile:

```bash
make perf-test BUCKET=<bucket-name> QUEUE=<queue-url> STATE_MACHINE=<state-machine-arn> FUNCTION=<function-name>
```

## Testing

Run the tests:

```bash
poetry run pytest
```

Or use the Makefile:

```bash
make test
```

## Infrastructure (Terraform)

Infrastructure code is located in `src/terraform`. It creates:

- S3 bucket with EventBridge notifications
- EventBridge rule to route events to SQS
- SQS queue with dead-letter queue
- Lambda function for processing objects
- Step Functions state machine for staggered invocation
- IAM roles and policies
- CloudWatch scheduled rule to trigger Step Functions

## Application Logic (Python 3.13)

- `simulate_uploads.py`: Simulates uploading many objects to S3 in parallel
- `process_object.py`: Lambda function to process objects
- `monitor_processing.py`: Script to monitor processing status

## Implementation Details

### Staggered Lambda Invocation

The Step Functions state machine implements a sophisticated pattern that staggers Lambda invocations to prevent overwhelming downstream systems:

1. **Controlled Polling**: Retrieves up to 10 messages from SQS in a single batch
2. **Parallel Processing with Limits**: Uses a Map state to process each message in parallel, with configurable concurrency limits (default: 3)
3. **Dynamic Wait Times**: Inside the Map state, uses a Wait state with a calculated delay based on:
   - Item index in the batch (0-9)
   - Current SQS queue depth
   - Priority level from the message attributes
4. **Adaptive Scheduling**: As Lambda functions complete, new ones are invoked according to the staggered schedule
5. **Backpressure Handling**: Automatically slows down processing when downstream systems show signs of stress

This staggered approach provides several advantages:
- Prevents overwhelming backend API systems
- Allows for priority-based processing
- Maintains consistent throughput without spikes
- Enables better resource utilization

### Simulated API Processing

The Lambda function demonstrates a realistic processing pattern:

1. **CSV Parsing**: Reads and parses CSV files from S3 using efficient streaming techniques
2. **Batch Processing**: Processes rows in configurable batch sizes
3. **API Integration**: For each row, makes simulated API calls with realistic latency (5-30 seconds)
4. **Failure Handling**: Implements retry logic with exponential backoff
5. **Comprehensive Logging**: Records detailed metrics and logs for monitoring
6. **Adaptive Throughput**: Adjusts processing speed based on API response times

The implementation provides a realistic test bed for evaluating performance and reliability in a production-like environment.

## Development Practices

This project follows modern development practices to ensure code quality, maintainability, and reliability:

### Code Quality

- **Dependency Management**: Poetry for reliable, reproducible Python dependency management
- **Code Validation**: Pre-commit hooks enforce standards before commits
- **Testing**: Pytest for unit testing with 90%+ code coverage
- **Formatting & Linting**: Ruff for consistent Python code style and quality
- **Type Checking**: Comprehensive type annotations with mypy validation
- **Security Scanning**: Bandit and Trivy for security vulnerability detection
- **Documentation**: Detailed README, architecture diagrams, and code comments

### Testing Strategy

- **Unit Tests**: Test individual functions and classes in isolation
- **Integration Tests**: Validate component interactions
- **Performance Tests**: Measure system throughput and latency
- **Security Tests**: Validate security controls and policies
- **Load Tests**: Verify system behavior under high load

### Working with Poetry

```bash
# Add a new dependency
poetry add boto3

# Add a development dependency
poetry add --group dev pytest-cov

# Update dependencies
poetry update

# Activate the virtual environment
poetry shell

# Run a command within the virtual environment
poetry run python src/python/simulate_uploads.py

# Run tests with coverage report
poetry run pytest --cov=src/python

# Export dependencies to requirements.txt
poetry export -f requirements.txt --output requirements.txt
```

### Continuous Integration

The project is configured with pre-commit hooks to enforce standards:

```bash
# Run all pre-commit hooks
pre-commit run --all-files

# Run specific hooks
pre-commit run ruff
pre-commit run terraform-fmt

# Automatically fix issues
poetry run ruff check --fix src/python/
poetry run ruff format src/python/
```
