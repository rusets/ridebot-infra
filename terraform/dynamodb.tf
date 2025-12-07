############################################
# DynamoDB Table — Trips
# Purpose: single-table schema (pk/sk)
############################################
# tfsec:ignore:aws-dynamodb-table-customer-key
resource "aws_dynamodb_table" "trips" {
  name         = "${var.project_name}-trips"
  billing_mode = var.dynamodb_billing_mode

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "trip_id"
    type = "S"
  }

  global_secondary_index {
    name            = "trip-id-index"
    hash_key        = "trip_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project = var.project_name
  }
}
