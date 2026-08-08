# Remote state backend for GCP environments.
#
# Applied once, with local state. See ../README.md.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  # Deliberately no backend block: this is what creates the backend.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "state" {
  # Bucket names are globally unique, so the project ID is part of it.
  name     = "${var.project_id}-skyl-tfstate"
  location = var.region

  # GCS provides strong consistency and object-level locking, so unlike S3
  # there is no separate lock table to run.
  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # State is versioned forever in effect: 10 noncurrent versions is far more
  # history than any recovery needs, and the objects are kilobytes.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  # A `terraform destroy` here would take every environment's state with it.
  force_destroy = false

  labels = {
    managed-by = "terraform"
    part-of    = "skyl"
    purpose    = "tfstate"
  }
}
