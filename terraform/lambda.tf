# ------------------------------------------------------
# Package Lambda source code into a ZIP file
# Terraform will archive the contents of ../lambda_src
# into ../lambda_src.zip before deploying.
# ------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"                                 # archive format
  source_dir  = "${path.module}/../lambda_src"        # source code directory
  output_path = "${path.module}/../lambda_src.zip"    # output .zip file path
}

# ------------------------------------------------------
# AWS Lambda Function
# Handles Telegram webhook requests via API Gateway.
# ------------------------------------------------------
resource "aws_lambda_function" "handler" {
  # Name of the Lambda function (will appear in AWS console)
  function_name = "${var.project_name}-handler"

  # IAM role that Lambda assumes at runtime (defined in iam.tf)
  role = aws_iam_role.lambda_role.arn

  # Entrypoint: app.py → function lambda_handler(event, context)
  handler = "app.lambda_handler"

  # Python runtime version
  runtime = "python3.12"

  # Deployment package
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  # source_code_hash ensures Lambda is updated only if the code actually changes

  # Timeout (seconds) — maximum runtime before function is killed
  timeout = 10

  # ------------------------------------------------------
  # Environment variables passed to Lambda
  # These are used in app.py to access resources and fare rules.
  # ------------------------------------------------------
  environment {
    variables = {
      # DynamoDB table name
      TABLE_NAME = aws_dynamodb_table.trips.name

      # Amazon Location resources
      PLACE_INDEX_NAME      = aws_location_place_index.places.index_name
      ROUTE_CALCULATOR_NAME = aws_location_route_calculator.routes.calculator_name

      # Secrets stored in SSM Parameter Store
      SSM_TOKEN_PARAM  = data.aws_ssm_parameter.telegram_token.name   # Telegram bot token
      SSM_DRIVER_PARAM = data.aws_ssm_parameter.driver_chat_id.name   # Driver chat ID(s)

      # Fare calculation rules (editable without redeploying Lambda code)
      FARE_BASE     = "3.0"   # base fare ($)
      FARE_PER_MILE = "1.5"   # cost per mile
      FARE_PER_MIN  = "0.35"  # cost per minute
      FARE_FEE      = "1.0"   # service/booking fee
      FARE_SURGE    = "1.0"   # surge multiplier
      FARE_MINIMUM  = "8.0"   # minimum fare ($)
    }
  }

  # Tags (for cost allocation and organization)
  tags = {
    Project = var.project_name
  }
}