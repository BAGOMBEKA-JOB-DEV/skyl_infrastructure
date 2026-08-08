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

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 rather than KMS. State is already access-controlled, and a KMS
      # key adds a per-request charge plus one more thing whose deletion locks
      # you out of your own state.
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
