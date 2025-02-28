# Example: S3 Event Processor Module

This example demonstrates how to use the `s3-event-processor` module to create a staggered Lambda invocation pattern for processing S3 objects.

## Usage

To use this example:

1. Review the variables in `variables.tf` and modify as needed
2. Initialize Terraform:

```bash
terraform init
```

3. Preview the infrastructure changes:

```bash
terraform plan
```

4. Apply the changes:

```bash
terraform apply
```

## Examples

The example includes two implementations:

1. `process_objects` - Creates a new S3 bucket and sets up the staggered processing pipeline
2. `process_objects_existing_bucket` - Uses an existing S3 bucket (requires updating the bucket ID and ARN)

## Important Notes

- Update the `existing_bucket_id` and `existing_bucket_arn` variables with your actual bucket details before applying the second example.
- The examples showcase different configurations for Lambda scaling and Step Functions concurrency.
- Both examples use the same Lambda handler function - in a real-world scenario, you would use different functions as needed.

## Clean Up

To destroy the created resources:

```bash
terraform destroy
```
