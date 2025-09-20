# Amazon Location Service resources
resource "aws_location_place_index" "places" {
  index_name  = "${var.project_name}-places"
  data_source = "Here"
}

resource "aws_location_route_calculator" "routes" {
  calculator_name = "${var.project_name}-routes"
  data_source     = "Here"
}