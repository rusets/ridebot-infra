output "api_base_url" {
  value = trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")
}


output "webhook_url" {
  description = "Complete Telegram webhook URL"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/telegram/webhook"
}

output "dynamodb_table" {
  value = aws_dynamodb_table.trips.name
}

output "place_index_name" {
  value = aws_location_place_index.places.index_name
}

output "route_calculator_name" {
  value = aws_location_route_calculator.routes.calculator_name
}


output "current_telegram_webhook" {
  value = "${trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")}/telegram/webhook"
}