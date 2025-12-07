############################################
# IAM — Lambda Execution Role
# Purpose: trust policy for AWS Lambda service
############################################
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

############################################
# IAM — Lambda Policy Document
# Purpose: least-privilege access for Lambda
############################################
data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    sid    = "DynamoDBTableItems"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      aws_dynamodb_table.trips.arn
    ]
  }

  statement {
    sid    = "DynamoDBQuery"
    effect = "Allow"
    actions = [
      "dynamodb:Query"
    ]
    resources = [
      aws_dynamodb_table.trips.arn,
      "${aws_dynamodb_table.trips.arn}/index/trip-id-index"
    ]
  }

  statement {
    sid    = "SSMParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/ridebot/*"
    ]
  }

  statement {
    sid    = "KMSDecryptForSSM"
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
    ]
  }

  statement {
    sid    = "AmazonLocation"
    effect = "Allow"
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

############################################
# IAM — Managed Policy for Lambda
# Purpose: attach generated policy JSON
############################################
resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

############################################
# IAM — Policy Attachment
# Purpose: link policy to Lambda role
############################################
resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
