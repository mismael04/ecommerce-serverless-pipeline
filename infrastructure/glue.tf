# --- Glue Database & Crawler ---
resource "aws_glue_catalog_database" "ecommerce_db" {
  name = "ecommerce_data_lake"
}

resource "aws_iam_role" "crawler_role" {
  name = "glue_crawler_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "crawler_service" {
  role       = aws_iam_role.crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "crawler_s3" {
  name = "crawler_s3_read"
  role = aws_iam_role.crawler_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.processed_zone.arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "ecommerce_crawler" {
  database_name = aws_glue_catalog_database.ecommerce_db.name
  name          = "ecommerce-parquet-crawler"
  role          = aws_iam_role.crawler_role.arn
  
  s3_target { 
    path = "s3://${aws_s3_bucket.processed_zone.id}/" 
  }
  
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
  
  tags = local.common_tags
}

# --- Glue ETL Job & IAM ---
resource "aws_iam_role" "glue_role" {
  name = "glue_etl_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_least_privilege" {
  name = "glue_s3_least_privilege"
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Action = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.raw_zone.arn, aws_s3_bucket.processed_zone.arn, aws_s3_bucket.scripts.arn]
      },
      {
        Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.raw_zone.arn}/*", "${aws_s3_bucket.processed_zone.arn}/*", "${aws_s3_bucket.scripts.arn}/*"]
      }
    ]
  })
}

resource "aws_glue_job" "etl_job" {
  name     = "ecommerce-cleanse-job"
  role_arn = aws_iam_role.glue_role.arn
  command {
    script_location = "s3://${aws_s3_bucket.scripts.id}/scripts/glue_job.py"
    python_version  = "3"
  }
  execution_class   = "STANDARD"
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  tags              = local.common_tags
}