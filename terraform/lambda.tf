data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_src"
  output_path = "${path.module}/../lambda_src.zip"
}

resource "aws_lambda_function" "handler" {
  function_name = "${var.project_name}-handler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout = 10

  environment {
    variables = {
      TABLE_NAME            = aws_dynamodb_table.trips.name
      PLACE_INDEX_NAME      = aws_location_place_index.places.index_name
      ROUTE_CALCULATOR_NAME = aws_location_route_calculator.routes.calculator_name
      SSM_TOKEN_PARAM       = data.aws_ssm_parameter.telegram_token.name
      SSM_DRIVER_PARAM      = data.aws_ssm_parameter.driver_chat_id.name
      # Fare rules (tweak without redeploy)
      FARE_BASE             = "3.0"
      FARE_PER_MILE         = "1.5"
      FARE_PER_MIN          = "0.35"
      FARE_FEE              = "1.0"
      FARE_SURGE            = "1.0"
      FARE_MINIMUM          = "8.0"
    }
  }

  tags = {
    Project = var.project_name
  }
}
