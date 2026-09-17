# SNS Topic for Pipeline Alerts & Failures
resource "aws_sns_topic" "alerts" {
  name = "ecommerce-pipeline-alerts"
  tags = local.common_tags
}

# Email subscription to notify you on production pipeline failures
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "m.ismael.uf@gmail.com"
}

# CloudWatch Metric Alarm for Step Functions Failures
resource "aws_cloudwatch_metric_alarm" "sfn_failure" {
  alarm_name          = "ecommerce-sfn-execution-failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alarm triggers if the e-commerce ETL orchestration workflow fails."
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.etl_orchestrator.arn
  }
  tags = local.common_tags
}

# CloudWatch Metric Alarm for Lambda Validator Errors
resource "aws_cloudwatch_metric_alarm" "lambda_error" {
  alarm_name          = "ecommerce-lambda-validator-failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alarm triggers if the schema validator Lambda catches invalid data."
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.validator.function_name
  }
  tags = local.common_tags
}