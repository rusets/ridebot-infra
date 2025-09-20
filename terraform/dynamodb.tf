# ------------------------------------------------------
# DynamoDB table definition
# Purpose: Store all ride requests, their statuses, and driver assignments
# Design: Single-table pattern using composite keys (pk + sk)
# ------------------------------------------------------
resource "aws_dynamodb_table" "trips" {
  # Table name (unique per account/region)
  # Example: ridebot-trips
  name = "${var.project_name}-trips"

  # Billing mode: 
  # - PAY_PER_REQUEST (default for serverless apps, scales automatically)
  # - PROVISIONED (you manually set RCU/WCU)
  # Controlled via variable dynamodb_billing_mode
  billing_mode = var.dynamodb_billing_mode

  # -----------------------------
  # Primary keys
  # -----------------------------
  # Partition key (pk): groups all related items together (e.g., TRIP#123)
  hash_key  = "pk"
  # Sort key (sk): differentiates multiple records within the same partition
  # Example: TRIP#123 + META (main data), TRIP#123 + STATUS#1, etc.
  range_key = "sk"

  # Define attribute types for keys
  attribute {
    name = "pk"
    type = "S" # String type
  }

  attribute {
    name = "sk"
    type = "S" # String type
  }

  # -----------------------------
  # Extra attribute for queries
  # -----------------------------
  # trip_id is stored separately to support direct lookups
  # Example: when Telegram sends callback with trip_id,
  # you can query by this field via the GSI
  attribute {
    name = "trip_id"
    type = "S"
  }

  # -----------------------------
  # Global Secondary Index (GSI)
  # -----------------------------
  # trip-id-index allows direct lookup by trip_id
  # Hash key = trip_id (string)
  # Projection type = ALL (returns all item attributes when queried)
  global_secondary_index {
    name            = "trip-id-index"
    hash_key        = "trip_id"
    projection_type = "ALL"
  }

  # -----------------------------
  # Tags (for billing and organization)
  # -----------------------------
  tags = {
    Project = var.project_name
  }
}