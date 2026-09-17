# Amazon CloudWatch alarms: tell someone when the assistant breaks or slows down.
# Logs and X-Ray traces are set up with each Lambda function (lambda.tf) and the API (api_gateway.tf).

resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email # AWS sends a confirmation email first
}

# Any Lambda error in 5 minutes, for the chat and ingest functions
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(["chat", "ingest"])

  alarm_name          = "${local.name}-${each.key}-errors"
  alarm_description   = "The ${each.key} function failed"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.app[each.key].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# Server errors returned to people (502 = assistant unavailable, 503/504 = timeouts)
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name}-api-5xx"
  alarm_description   = "People are getting server errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.chat.id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# Slow answers: the slowest 10% take over 20 seconds (the API gives up at 30)
resource "aws_cloudwatch_metric_alarm" "chat_slow" {
  alarm_name          = "${local.name}-chat-slow"
  alarm_description   = "Answers are getting close to the 30 second API limit"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = aws_lambda_function.app["chat"].function_name }
  extended_statistic  = "p90"
  period              = 300
  evaluation_periods  = 2
  threshold           = 20000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
