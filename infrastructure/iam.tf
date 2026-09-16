# --- AWS STEP FUNCTIONS ORCHESTRATOR & IAM ---
resource "aws_iam_role" "sfn_role" {
  name = "sfn_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "sfn_glue_invocation" {
  name = "sfn_glue_invocation"
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Action = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = "*"
      },
      {
        Effect = "Allow", Action = ["glue:StartCrawler", "glue:GetCrawler"]
        Resource = aws_glue_crawler.ecommerce_crawler.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "etl_orchestrator" {
  name     = "EcommerceETLOrchestrator"
  role_arn = aws_iam_role.sfn_role.arn
  tags     = local.common_tags

  definition = jsonencode({
    Comment = "Orchestrates ETL processing ONLY the file that triggered the event, then runs Crawler",
    StartAt = "Run Glue Job",
    States = {
      "Run Glue Job" = {
        Type = "Task", 
        Resource = "arn:aws:states:::glue:startJobRun.sync",
        Parameters = { 
          JobName = aws_glue_job.etl_job.name,
          Arguments = { 
            "--source_bucket.$" = "$.detail.bucket.name",
            "--source_key.$"    = "$.detail.object.key",
            "--target_path"     = "s3://${aws_s3_bucket.processed_zone.id}/"
          }
        },
        Retry = [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 3, MaxAttempts = 2, BackoffRate = 1.5 }],
        Next = "Start Crawler"
      },
      "Start Crawler" = {
        Type = "Task", Resource = "arn:aws:states:::aws-sdk:glue:startCrawler",
        Parameters = { Name = aws_glue_crawler.ecommerce_crawler.name },
        Next = "Wait For Crawler"
      },
      "Wait For Crawler" = {
        Type = "Wait", Seconds = 30, Next = "Check Crawler Status"
      },
      "Check Crawler Status" = {
        Type = "Task", Resource = "arn:aws:states:::aws-sdk:glue:getCrawler",
        Parameters = { Name = aws_glue_crawler.ecommerce_crawler.name },
        Next = "Is Crawler Running?"
      },
      "Is Crawler Running?" = {
        Type = "Choice",
        Choices = [
          { Variable = "$.Crawler.State", StringEquals = "RUNNING", Next = "Wait For Crawler" },
          { Variable = "$.Crawler.State", StringEquals = "STOPPING", Next = "Wait For Crawler" }
        ],
        Default = "Done"
      },
      "Done" = { Type = "Succeed" }
    }
  })
}

# --- AMAZON EVENTBRIDGE TRIGGER ---
resource "aws_cloudwatch_event_rule" "s3_trigger" {
  name          = "trigger-on-s3-upload"
  event_pattern = jsonencode({
    source = ["aws.s3"], detail-type = ["Object Created"], detail = { bucket = { name = [aws_s3_bucket.raw_zone.id] } }
  })
  tags = local.common_tags
}

resource "aws_iam_role" "eventbridge_role" {
  name = "eventbridge_sfn_invocation_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "events.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "eb_policy" {
  role = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [{ Action = "states:StartExecution", Effect = "Allow", Resource = aws_sfn_state_machine.etl_orchestrator.arn }]
  })
}

resource "aws_cloudwatch_event_target" "sfn_target" {
  rule      = aws_cloudwatch_event_rule.s3_trigger.name
  target_id = "TriggerStepFunction"
  arn       = aws_sfn_state_machine.etl_orchestrator.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}