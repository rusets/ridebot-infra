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

  # For quick lookup by trip_id in callbacks
  attribute {
    name = "trip_id"
    type = "S"
  }

  global_secondary_index {
    name            = "trip-id-index"
    hash_key        = "trip_id"
    projection_type = "ALL"
  }

  tags = {
    Project = var.project_name
  }
}
