# =============================================================================
# BOOTSTRAP CONFIG — run this ONCE, manually, with local state, BEFORE
# touching the root Terraform config.
#
# Why this exists: the root config's backend.tf points at an S3 bucket for
# remote state. That bucket has to exist before `terraform init` can use it
# as a backend — so it can't be created by the same config that depends on
# it. This bootstrap config creates just that one bucket, with a local
# .tfstate file that you keep (or discard once the bucket exists — it's a
# tiny, essentially static resource you won't touch again).
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   # note the bucket name in the output, then go set it in
#   # terraform/backend.tf and run `terraform init` there.
# =============================================================================

terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Intentionally local state — this is the one config allowed to have it.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "tinyuka-2025-capstone"
    }
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique name for the Terraform remote state bucket"
  type        = string
  # No default on purpose — pick something unique to you, e.g.:
  # "bedrock-tfstate-<your-student-id-sanitized>"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` from silently deleting your state bucket.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "state_bucket_region" {
  value = var.aws_region
}
