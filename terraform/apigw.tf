# --------------------------------------------
# API Gateway v2 (HTTP API) for Telegram webhook
# --------------------------------------------
resource "aws_apigatewayv2_api" "http" {
  # Human-readable API name
  name          = "${var.project_name}-api"

  # HTTP API (v2) is cheaper and simpler than REST API (v1)
  protocol_type = "HTTP"
}

# --------------------------------------------
# Lambda integration (AWS_PROXY) using HTTP API v2
# --------------------------------------------
resource "aws_apigatewayv2_integration" "lambda" {
  # Attach integration to the HTTP API created above
  api_id = aws_apigatewayv2_api.http.id

  # Use Lambda proxy integration so the function handles request/response mapping
  integration_type = "AWS_PROXY"

  # HTTP method API Gateway uses to call the integration
  integration_method = "POST"

  # Lambda invoke ARN (includes version qualifier handling by AWS)
  integration_uri = aws_lambda_function.handler.invoke_arn

  # Payload format 2.0 is required for HTTP API v2 + Lambda proxy
  payload_format_version = "2.0"
}

# --------------------------------------------
# Route: POST /telegram/webhook -> Lambda integration
# --------------------------------------------
resource "aws_apigatewayv2_route" "telegram_webhook" {
  api_id = aws_apigatewayv2_api.http.id

  # Route key format for HTTP APIs: "<METHOD> <PATH>"
  route_key = "POST /telegram/webhook"

  # Bind the route to the integration created above
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# --------------------------------------------
# Stage configuration
# - auto_deploy=true publishes every route/integration change automatically
# --------------------------------------------
resource "aws_apigatewayv2_stage" "prod" {
  api_id = aws_apigatewayv2_api.http.id

  # Stage name becomes part of the invoke URL: .../prod/...
  name        = "prod"

  # No need to create deployments manually
  auto_deploy = true
}

# --------------------------------------------
# Permission for API Gateway to invoke the Lambda function
# - principal must be "apigateway.amazonaws.com"
# - source_arn limits who can invoke (this API execution ARN, any route/method)
# --------------------------------------------
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"

  # Match the function created elsewhere (aws_lambda_function.handler)
  function_name = aws_lambda_function.handler.function_name

  # API Gateway principal
  principal     = "apigateway.amazonaws.com"

  # Allow any method/route from this API/stage to invoke the Lambda
  # Pattern: ${api.execution_arn}/*/*  ->  /*(stage)/*(route+method)
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}