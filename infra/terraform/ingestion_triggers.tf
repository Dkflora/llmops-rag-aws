# When ingestion runs:
#   1. whenever manifest.json is uploaded to the documents bucket (documents changed)
#   2. once a day, as a safety net

# 1. S3 upload of manifest.json
resource "aws_lambda_permission" "ingest_from_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app["ingest"].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents.arn
}

resource "aws_s3_bucket_notification" "documents" {
  bucket = aws_s3_bucket.documents.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.app["ingest"].arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = "manifest.json" # upload the policy files first, the manifest last
  }

  depends_on = [aws_lambda_permission.ingest_from_s3]
}

# 2. Daily schedule with Amazon EventBridge
resource "aws_cloudwatch_event_rule" "daily_ingest" {
  name                = "${local.name}-daily-ingest"
  description         = "Rebuild the policy index once a day"
  schedule_expression = "cron(0 6 * * ? *)" # 06:00 UTC every day
}

resource "aws_cloudwatch_event_target" "daily_ingest" {
  rule = aws_cloudwatch_event_rule.daily_ingest.name
  arn  = aws_lambda_function.app["ingest"].arn
}

resource "aws_lambda_permission" "ingest_from_schedule" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app["ingest"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_ingest.arn
}
