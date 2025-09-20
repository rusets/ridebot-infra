# ------------------------------------------------------
# Terraform Outputs
# These values are printed after "terraform apply"
# and can be used by other modules, scripts, or humans.
# ------------------------------------------------------

# Base API Gateway invoke URL (without trailing slash)
# Example: https://abc123.execute-api.us-east-1.amazonaws.com/prod
output "api_base_url" {
  value = trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")
}

# Full Telegram webhook URL (for setting up the bot webhook)
# Example: https://abc123.execute-api.us-east-1.amazonaws.com/prod/telegram/webhook
output "webhook_url" {
  description = "Complete Telegram webhook URL"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/telegram/webhook"
}

# DynamoDB table name for storing trip data
output "dynamodb_table" {
  value = aws_dynamodb_table.trips.name
}

# Amazon Location Service: Place Index name
# Used for address lookups (geocoding and reverse geocoding)
output "place_index_name" {
  value = aws_location_place_index.places.index_name
}

# Amazon Location Service: Route Calculator name
# Used for trip distance and time calculations
output "route_calculator_name" {
  value = aws_location_route_calculator.routes.calculator_name
}

# Current webhook URL (alternative form)
# Equivalent to webhook_url, but ensures base URL has no trailing slash
output "current_telegram_webhook" {
  value = "${trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")}/telegram/webhook"
}