# Remote state backend for AWS environments.
#
# Applied once, with local state. See ../README.md.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  # S3 bucket names are globally unique across all AWS accounts.
  bucket_name = "skyl-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate"
  }
}

# Access logs for the state bucket: who read and wrote state, and when.
#
# A separate bucket, because a bucket cannot log to itself — S3 rejects the
# configuration, and if it did not, every write would log a write.
#
# trivy:ignore:AWS-0089 the log bucket does not log its own access; that is the recursion above
# trivy:ignore:AWS-0132 SSE-S3 rather than a CMK, for the reason given on the state bucket below
resource "aws_s3_bucket" "logs" {
  bucket = "${local.bucket_name}-logs"

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate-access-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# trivy:ignore:AWS-0132 SSE-S3, for the same reason as the state bucket: a CMK adds a deletion path that permanently destroys access to the data it protects
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioned like the state bucket. Access logs are audit evidence, and audit
# evidence that can be silently overwritten is not evidence.
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 log delivery writes with the log-delivery-write canned ACL, which requires
# ACLs to be enabled on the destination. Buckets created today default to
# BucketOwnerEnforced, which disables ACLs entirely and makes log delivery fail
# silently — no error, just no logs.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    # Failed multipart uploads are invisible in the console and billed until
    # cleaned up. Seven days is long enough for a retry, short enough that the
    # charge never becomes noticeable.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "tfstate-access/"

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# trivy:ignore:AWS-0132 SSE-S3 chosen deliberately; rationale in the comment below
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 rather than KMS. State is already access-controlled, and a KMS
      # key adds a per-request charge plus one more thing whose deletion locks
      # you out of your own state — permanently, since a scheduled key deletion
      # cannot be undone after the window closes.
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State contains resource attributes that are secrets in practice. Deny any
# request that is not over TLS, so a misconfigured client cannot fetch it in
# plaintext.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# S3 gained conditional writes in 2024, so `use_lockfile` in the backend can
# replace this. The table is kept because it works on every Terraform version
# and costs pennies on-demand — a locking mechanism is the wrong place to be
# on the leading edge.
# trivy:ignore:AWS-0025 AWS-owned key is sufficient: the table holds lock IDs and timestamps, no state contents
resource "aws_dynamodb_table" "lock" {
  name         = "skyl-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate-lock"
  }
}
