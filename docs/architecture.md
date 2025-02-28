# Architecture Diagram

The following diagram illustrates the complete flow of data through the S3 EventBridge SQS Lambda architecture.

```mermaid
flowchart TD
    %% Data Flow
    Client([Client]) -->|Upload CSV Files| S3[S3 Bucket]
    S3 -->|Object Created Events| EB[EventBridge]
    EB -->|Route Events| SQS[SQS Queue]
    SQS -->|Dead Letter| SQS_DLQ[SQS DLQ]
    SQS -->|Poll Messages| SF[Step Functions]
    SF -->|Staggered Invocation| Lambda[Lambda Function]
    Lambda -->|Read Objects| S3
    Lambda -->|Dead Letter| Lambda_DLQ[Lambda Destination DLQ]
    Lambda -->|Call API| ExternalAPI[External API]
    Lambda -->|Structured Logs| Logs[CloudWatch Logs]

    %% Monitoring & Observability
    Logs -->|Forward| Splunk[Splunk Index]
    Metrics[CloudWatch Metrics] -->|Sync| DynaTrace[DynaTrace Dashboard]

    %% Monitoring Connections
    CloudWatch[CloudWatch Alarms] -->|Monitor| SQS
    CloudWatch -->|Monitor| SF
    CloudWatch -->|Monitor| Lambda
    DynaTrace -->|APM Monitoring| Lambda
    DynaTrace -->|APM Monitoring| SF
    Splunk -->|Log Analysis| Lambda

    %% Scaling
    AutoScaling[Auto Scaling] -->|Scale| Lambda
    SQS -->|Queue Depth Metric| AutoScaling

    %% Error Handling
    DLQProcessor[DLQ Processor] -->|Redrive| SQS_DLQ
    DLQProcessor -->|Redrive| Lambda_DLQ

    %% SMTP Integration
    Alerts[Alert Manager] -->|Email| SMTP[SMTP Server]
    CloudWatch -->|Trigger| Alerts

    %% Styling
    style S3 fill:#FF9900,stroke:#FF9900,color:white
    style EB fill:#FF4F8B,stroke:#FF4F8B,color:white
    style SQS fill:#FF9900,stroke:#FF9900,color:white
    style SQS_DLQ fill:#FF9900,stroke:#FF9900,color:white,stroke-dasharray: 5 5
    style SF fill:#FF9900,stroke:#FF9900,color:white
    style Lambda fill:#FF9900,stroke:#FF9900,color:white
    style Lambda_DLQ fill:#FF9900,stroke:#FF9900,color:white,stroke-dasharray: 5 5
    style CloudWatch fill:#FF4F8B,stroke:#FF4F8B,color:white
    style DynaTrace fill:#008CFF,stroke:#008CFF,color:white
    style AutoScaling fill:#FF4F8B,stroke:#FF4F8B,color:white
    style ExternalAPI fill:#1EC9E8,stroke:#1EC9E8,color:white
    style Logs fill:#FF4F8B,stroke:#FF4F8B,color:white
    style Metrics fill:#FF4F8B,stroke:#FF4F8B,color:white
    style Splunk fill:#65A637,stroke:#65A637,color:white
    style DLQProcessor fill:#FF4F8B,stroke:#FF4F8B,color:white
    style Alerts fill:#FF4F8B,stroke:#FF4F8B,color:white
    style SMTP fill:#232F3E,stroke:#232F3E,color:white
```

## Architecture Components

### Data Flow Components
- **S3 Bucket**: Storage for uploaded CSV files
- **EventBridge**: Routes S3 object events to SQS
- **SQS Queue**: Buffers events with DLQ for failed deliveries
- **Step Functions**: Orchestrates staggered Lambda invocations
- **Lambda Function**: Processes S3 objects with controlled concurrency

### Monitoring & Observability
- **CloudWatch**: Alarms, metrics, and logs for AWS services
- **Dynatrace**: Primary APM tool for metrics and performance monitoring
- **Splunk**: Primary log analytics platform for Lambda logs
- **SMTP Server**: Central email delivery for notifications

### Reliability Features
- **DLQ Processor**: Handles failed message redriving
- **Auto Scaling**: Adjusts Lambda concurrency based on queue depth

## Key Architectural Patterns

1. **Event-Driven Architecture**: Loosely coupled components communicating via events
2. **Throttled Processing**: Controlled concurrency through Step Functions
3. **At-Least-Once Delivery**: DLQs ensure message delivery reliability
4. **Comprehensive Observability**: Multi-tool monitoring approach
5. **Auto-Scaling**: Dynamic resource allocation based on demand
