# Amazon API Gateway (HTTP API): the front door for the chat Lambda.
#
#   validate JWT   the Cognito ID token is checked before Lambda runs
#   route          each path goes to the chat function
#   throttle       limits requests per second, so nobody can run up the Bedrock bill

resource "aws_apigatewayv2_api" "chat" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  name             = "cognito"
  api_id           = aws_apigatewayv2_api.chat.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://${aws_cognito_user_pool.main.endpoint}"
    audience = [aws_cognito_user_pool_client.web.id] # tokens for our app only
  }
}

resource "aws_apigatewayv2_integration" "chat" {
  api_id                 = aws_apigatewayv2_api.chat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app["chat"].invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

locals {
  # route => does it need a signed-in user?
  routes = {
    "GET /api/health"                      = false
    "GET /api/me"                          = true
    "GET /api/conversations"               = true
    "GET /api/conversations/{id}/messages" = true
    "POST /api/chat"                       = true
  }
}

resource "aws_apigatewayv2_route" "chat" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.chat.id}"
  authorization_type = each.value ? "JWT" : "NONE"
  authorizer_id      = each.value ? aws_apigatewayv2_authorizer.cognito.id : null
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name}-api"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.chat.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 10 # requests per second, on average
    throttling_burst_limit = 20 # short bursts
  }

  # One line per request: who, what, status, how long
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId = "$context.requestId"
      time      = "$context.requestTime"
      route     = "$context.routeKey"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      email     = "$context.authorizer.claims.email"
      error     = "$context.authorizer.error"
    })
  }
}

resource "aws_lambda_permission" "chat_from_api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app["chat"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat.execution_arn}/*/*"
}
