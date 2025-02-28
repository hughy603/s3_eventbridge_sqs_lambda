/**
 * # S3 Module
 *
 * This module creates an S3 bucket with proper security configurations
 * and event notifications to EventBridge.
 */

# Random string to append to resource names for uniqueness
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket for the objects
resource "aws_s3_bucket" "this" {
  bucket = "${var.name_prefix}-objects-${random_string.suffix.result}"

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-objects"
    }
  )
}

# Block public access
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Enable access logging if configured
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket_name != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = "${var.name_prefix}-objects-access-logs/"
}

# Configure lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.enable_lifecycle_rules ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# S3 Event notification to EventBridge
resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  eventbridge = true
}
