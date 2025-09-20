# ------------------------------------------------------
# IAM Role and Policy for Lambda function
# Purpose: Grant Lambda only the permissions it needs
# ------------------------------------------------------

# IAM role that the Lambda function will assume when running
resource "aws_iam_role" "lambda_role" {
  # Role name (includes project prefix for uniqueness)
  name = "${var.project_name}-lambda-role"

  # Trust policy: which service is allowed to assume this role
  # Here only AWS Lambda service (lambda.amazonaws.com)
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

# IAM policy document describing allowed actions
# This policy follows the least-privilege principle
data "aws_iam_policy_document" "lambda_policy_doc" {
  # ------------------------------------------------------
  # CloudWatch Logs
  # Lambda automatically writes logs to CloudWatch
  # Needed to create log groups/streams and push log events
  # ------------------------------------------------------
  statement {
    sid     = "Logs"
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  # ------------------------------------------------------
  # DynamoDB access (application data storage)
  # Lambda must read/write trip records in the DynamoDB table
  # ------------------------------------------------------
  statement {
    sid     = "DynamoDBTableAccess"
    effect  = "Allow"
    actions = [
      "dynamodb:PutItem",    # create new items
      "dynamodb:UpdateItem", # update trip status
      "dynamodb:GetItem",    # fetch trip details
      "dynamodb:Query",      # query by keys (pk/sk)
      "dynamodb:DeleteItem"  # remove records if needed
    ]
    resources = [
      aws_dynamodb_table.trips.arn,              # main table
      "${aws_dynamodb_table.trips.arn}/index/*"  # allow access to indexes (e.g. trip-id-index)
    ]
  }

  # ------------------------------------------------------
  # AWS Systems Manager (SSM) Parameter Store
  # Store and retrieve secrets (e.g., Telegram bot token, driver IDs)
  # ------------------------------------------------------
  statement {
    sid     = "SSMParams"
    effect  = "Allow"
    actions = [
      "ssm:GetParameter",        # read a single parameter
      "ssm:GetParametersByPath"  # read multiple parameters under /ridebot/*
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/ridebot/*"
    ]
  }

  # ------------------------------------------------------
  # KMS (Key Management Service)
  # Needed because SSM uses KMS to encrypt SecureString parameters
  # This allows Lambda to decrypt them at runtime
  # ------------------------------------------------------
  statement {
    sid     = "KMSDecryptForSSM"
    effect  = "Allow"
    actions = ["kms:Decrypt"]
    resources = [
      "arn:${data.aws_partition.current.partition}:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
    ]
  }

  # ------------------------------------------------------
  # Amazon Location Service
  # Provides geolocation features:
  # - SearchPlaceIndexForText: geocoding addresses
  # - SearchPlaceIndexForPosition: reverse geocoding
  # - CalculateRoute: distance/time between points
  # ------------------------------------------------------
  statement {
    sid     = "AmazonLocation"
    effect  = "Allow"
    actions = [
      "geo:SearchPlaceIndexForText",
      "geo:SearchPlaceIndexForPosition",
      "geo:CalculateRoute"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:geo:${var.aws_region}:${data.aws_caller_identity.current.account_id}:place-index/${aws_location_place_index.places.index_name}",
      "arn:${data.aws_partition.current.partition}:geo:${var.aws_region}:${data.aws_caller_identity.current.account_id}:route-calculator/${aws_location_route_calculator.routes.calculator_name}"
    ]
  }
}

# Create a managed IAM policy from the above document
resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

# Attach the IAM policy to the Lambda role
# This grants Lambda the permissions defined above
resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}