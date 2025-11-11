############################################
# Location — Place Index
# Purpose: convert addresses to coordinates
############################################
resource "aws_location_place_index" "places" {
  index_name  = "${var.project_name}-places"
  data_source = "Here"
}

############################################
# Location — Route Calculator
# Purpose: calculate distance and travel time
############################################
resource "aws_location_route_calculator" "routes" {
  calculator_name = "${var.project_name}-routes"
  data_source     = "Here"
}
