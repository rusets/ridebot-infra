############################################
# API Gateway — Telegram Webhook Endpoint
# Purpose: lightweight HTTP API v2 for Lambda proxy integration
############################################
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

############################################
# API Gateway Integration — Lambda Proxy
# Purpose: connect Telegram webhook route with Lambda handler
############################################
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.handler.invoke_arn
  payload_format_version = "2.0"
}

############################################
# API Gateway Route — POST /telegram/webhook
# Purpose: forward incoming Telegram requests to Lambda
############################################
resource "aws_apigatewayv2_route" "telegram_webhook" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /telegram/webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

############################################
# API Gateway Stage — prod
# Purpose: automatically deploy all routes/integrations
############################################
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "prod"
  auto_deploy = true
}

############################################
# Lambda Permission — Allow API Gateway Invoke
# Principle: least privilege; limit to this API execution ARN
############################################
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
