# IAM Role for Lambda Validator
resource "aws_iam_role" "lambda_exec" {
  name = "ecommerce_lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_read" {
  name = "lambda_s3_read_policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:ListBucket"],
      Resource = [
        aws_s3_bucket.raw_zone.arn,
        "${aws_s3_bucket.raw_zone.arn}/*"
      ]
    }]
  })
}

# IAM Policy for Lambda to start Step Functions executions
resource "aws_iam_role_policy" "lambda_sfn_invoke" {
  name = "lambda_sfn_invoke_policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "states:StartExecution",
      Resource = aws_sfn_state_machine.etl_orchestrator.arn
    }]
  })
}

# Archive source code for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/validator_lambda.py"
  output_path = "${path.module}/lambda_function.zip"
}

# AWS Lambda Function Resource
resource "aws_lambda_function" "validator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ecommerce-schema-validator"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "validator_lambda.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.etl_orchestrator.arn
    }
  }

  tags = local.common_tags
}