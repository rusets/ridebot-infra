# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

# IAM policy with least-privilege permissions
data "aws_iam_policy_document" "lambda_policy_doc" {
  # CloudWatch Logs
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

  # DynamoDB (app data)
  statement {
    sid     = "DynamoDBTableAccess"
    effect  = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:DeleteItem"
    ]
    resources = [
      aws_dynamodb_table.trips.arn,
      "${aws_dynamodb_table.trips.arn}/index/*"
    ]
  }

  # SSM Parameter Store (read app secrets)
  statement {
    sid     = "SSMParams"
    effect  = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/ridebot/*"
    ]
  }

  # KMS decrypt for SSM SecureString (AWS managed key)
  statement {
    sid     = "KMSDecryptForSSM"
    effect  = "Allow"
    actions = ["kms:Decrypt"]
    resources = [
      "arn:${data.aws_partition.current.partition}:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
    ]
  }

  # Amazon Location (Places + Routes)
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

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}