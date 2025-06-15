provider "aws" {
  region = var.region
}

# Generate a random number to ensure uniqueness
resource "random_integer" "suffix" {
  min = 1000
  max = 9999
}

locals {
  project     = var.project != "" ? var.project : terraform.workspace
  bucket_name = "${lower(local.project)}-${var.bucket_suffix}-${random_integer.suffix.result}"
}

resource "aws_s3_bucket" "project_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = local.bucket_name
    Environment = terraform.workspace
    Project     = local.project
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.project_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
