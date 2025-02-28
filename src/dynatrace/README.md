# Dynatrace Monitoring Integration

This directory contains Dynatrace monitoring configurations for the S3-EventBridge-SQS-Lambda pipeline.

## Overview

The Dynatrace dashboard provides comprehensive monitoring of the event-driven serverless architecture, including:

- S3 object uploads and events
- EventBridge event processing
- SQS queue metrics and DLQ monitoring
- Step Functions execution metrics and state transitions
- Lambda function performance, errors, and concurrency

## Setup Instructions

### 1. Deploy Dynatrace OneAgent

To monitor AWS services, deploy the Dynatrace OneAgent:

```bash
# Install OneAgent on EC2 instances/containers if applicable
wget -O Dynatrace-OneAgent-Linux.sh https://your-environment-id.live.dynatrace.com/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=YOUR_TOKEN
chmod +x Dynatrace-OneAgent-Linux.sh
sudo ./Dynatrace-OneAgent-Linux.sh --set-infra-only=false
```

### 2. Set Up AWS Integration

Configure the Dynatrace AWS integration to monitor AWS services:

1. In Dynatrace, go to **Settings > Cloud and virtualization > AWS**
2. Click **Connect new AWS account**
3. Set up an IAM role or provide credentials for Dynatrace to monitor AWS resources
4. Ensure the following services are enabled for monitoring:
   - AWS Lambda
   - AWS Step Functions
   - AWS SQS
   - AWS EventBridge
   - AWS S3

### 3. Import Dashboard

Import the dashboard JSON file into your Dynatrace environment:

1. Go to Dashboards in Dynatrace
2. Click "Import Dashboard"
3. Upload the `dashboard.json` file from this directory

### 4. Set Up Custom Logging

For Lambda functions, configure CloudWatch log integration with Dynatrace:

1. Add the Dynatrace Log Forwarder Lambda function
2. Configure CloudWatch subscription filters to forward logs to Dynatrace
3. Set up log parsing rules in Dynatrace for structured logs

### 5. Configure Alerts and Notification

Set up proper alerting in Dynatrace:

1. In Dynatrace, go to **Settings > Anomaly detection > Custom events for alerting**
2. Create custom alerting rules based on the metrics shown in the dashboard
3. Recommended alerts:
   - SQS DLQ messages > 0
   - Lambda errors > 0
   - Step Functions execution failures > 0
   - Lambda duration approaching timeout
   - SQS queue depth > threshold

### 6. Configure SMTP Email Integration

Since SNS cannot send email and all email must go through a central SMTP server:

1. Go to **Settings > Integration > Problem notifications**
2. Click **Set up notification**
3. Select **Email**
4. Configure the SMTP server settings:
   - SMTP server: your-smtp-server.example.com
   - Port: 587 (or appropriate for your SMTP server)
   - Protocol: STARTTLS/SSL as appropriate
   - Authentication: Username/password for your SMTP server
5. Configure notification content with appropriate templates

## Serverless Monitoring Best Practices

The dashboard and monitoring configurations follow these best practices:

### Lambda Monitoring

- Tracking cold starts and warm executions
- Memory utilization and provisioned concurrency usage
- Error rates and exception tracking
- Duration metrics with p95 and p99 percentiles
- DLQ monitoring for failed executions

### Step Functions Monitoring

- Execution status tracking
- Transition metrics between states
- Error rates and failure points
- End-to-end execution time

### SQS Monitoring

- Queue depth and processing rates
- Message age and visibility timeouts
- DLQ metrics and alerts
- Throttling events

### Alerting Configuration

The dashboard includes alert configurations for:

- High error rates in Lambda functions
- Step Functions execution failures
- SQS queue depth exceeding thresholds
- Messages appearing in DLQs
- End-to-end processing delays

## CloudWatch Mirroring

To ensure redundancy in monitoring, all Dynatrace metrics and alerts are mirrored in CloudWatch:

1. Critical Dynatrace alerts trigger CloudWatch events
2. CloudWatch dashboards provide a similar view as Dynatrace
3. All custom metrics collected in Dynatrace are also available in CloudWatch

## Splunk Integration

For organizations using Splunk as their primary monitoring tool:

1. Follow the setup instructions in the CloudWatch configuration for Splunk ingestion
2. Use the Splunk Add-on for AWS to ingest CloudWatch logs
3. Configure Dynatrace to forward alerts to Splunk via webhooks

## Dashboard Sections

The dashboard includes the following sections:

1. **Overview**: High-level health metrics for the entire pipeline
2. **SQS Queue Metrics**: Visualizes the number of messages in the queue
3. **Lambda Invocations**: Shows the rate of Lambda invocations
4. **Step Functions Executions**: Tracks Step Functions execution status
5. **Lambda Duration**: Monitors Lambda execution time
6. **Lambda Concurrent Executions**: Shows Lambda concurrency levels
7. **DLQ Messages**: Tracks dead-letter queue messages
8. **S3 Bucket Operations**: Monitors S3 object count
9. **EventBridge Invocations**: Shows EventBridge rule invocations
10. **Lambda Errors**: Tracks Lambda errors and throttles
11. **End-to-End Processing Time**: Tracks total processing time from S3 upload to completion

## Troubleshooting

If metrics are not showing up in your dashboard:

1. Verify AWS integration is properly configured
2. Check that AWS resource names/ARNs match the ones in the dashboard filters
3. Ensure your IAM roles have sufficient permissions for monitoring
4. Allow sufficient time for data to be collected (15-30 minutes)
5. Verify the SMTP server connectivity for alert notifications
