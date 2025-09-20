# ------------------------------------------------------
# Amazon Location Service resources
# Provides geocoding (addresses → coordinates) and routing.
# ------------------------------------------------------

# ------------------------------------------------------
# Place Index
# - Converts text addresses into geographic coordinates (geocoding).
# - Also supports reverse geocoding (coordinates → addresses).
# - Data source: "Here" (commercial maps provider).
# ------------------------------------------------------
resource "aws_location_place_index" "places" {
  # Name must be unique in your account/region
  index_name  = "${var.project_name}-places"

  # "Here" is the default commercial map data provider supported by AWS Location
  data_source = "Here"
}

# ------------------------------------------------------
# Route Calculator
# - Computes travel distance and time between two locations.
# - Used by the bot to estimate trip duration and fare.
# - Data source: "Here" (same as place index).
# ------------------------------------------------------
resource "aws_location_route_calculator" "routes" {
  # Name must be unique in your account/region
  calculator_name = "${var.project_name}-routes"

  # Same data provider used for routing calculations
  data_source     = "Here"
}