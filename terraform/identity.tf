############################################
# Data Sources — Identity & Partition
# Purpose: build ARNs dynamically without hardcoding
############################################
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
