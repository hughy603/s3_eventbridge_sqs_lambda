# S3 EventBridge SQS Lambda

Example application for testing S3 events being staggered to trigger Lambda at least once.  Infrastructure code is written in Terraform.  Application logic is written in Python 3.13.  Implements the following requirements.

  1. Use pre-commit to validate Terraform & Python Code according to industry best practices. Use ruff instead of black & isort
  2. Write test application to simulate a large number of objects being written to S3 in parallel.
  3. S3 Put Object events go to SQS
  4. Use parallel Step Functions to consume object from queue and kick off Lambdas in a staggered manner to not overload backend resources.
  5. Assume Lambda needs to read S3 object and call API for every row that takes 5-30s to return.
  6. Write unit tests for 90% code coverage
  7. Ensure `pre-commit run --all-files` does not return any errors
  8. Write documentation to ensure the example is easy to understand.

