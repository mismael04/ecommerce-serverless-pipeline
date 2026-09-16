output "raw_bucket_name" {
  value = aws_s3_bucket.raw_zone.id
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed_zone.id
}

output "step_functions_arn" {
  value = aws_sfn_state_machine.etl_orchestrator.arn
}