terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" { region = "us-east-1" }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  raw_bucket       = "ismael-ecommerce-raw"
  processed_bucket = "ismael-ecommerce-processed"
  scripts_bucket   = "ismael-ecommerce-scripts"
  athena_bucket    = "ismael-ecommerce-athena"
  
  suffix = "${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
  
  common_tags = {
    Project     = "Serverless-ETL"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# -------------------------------------------------------------------------
# 1. S3 BUCKETS
# -------------------------------------------------------------------------
resource "aws_s3_bucket" "raw_zone" { 
  bucket        = "${local.raw_bucket}-${local.suffix}"
  force_destroy = true
  tags          = local.common_tags 
}

resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket      = aws_s3_bucket.raw_zone.id
  eventbridge = true
}

resource "aws_s3_bucket" "processed_zone" { 
  bucket        = "${local.processed_bucket}-${local.suffix}"
  force_destroy = true
  tags          = local.common_tags 
}

resource "aws_s3_bucket" "scripts" { 
  bucket        = "${local.scripts_bucket}-${local.suffix}"
  force_destroy = true
  tags          = local.common_tags 
}

resource "aws_s3_bucket" "athena_results" { 
  bucket        = "${local.athena_bucket}-${local.suffix}"
  force_destroy = true
  tags          = local.common_tags 
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/glue_job.py"
  source = "../src/glue_job.py"
  etag   = filemd5("../src/glue_job.py")
}

# -------------------------------------------------------------------------
# 2. ATHENA WORKGROUP
# -------------------------------------------------------------------------
resource "aws_athena_workgroup" "analytics_wg" {
  name = "ecommerce-analytics-wg"
  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/"
    }
  }
  force_destroy = true
  tags          = local.common_tags
}