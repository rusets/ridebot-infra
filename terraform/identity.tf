# ------------------------------------------------------
# Identity & Partition data sources
# These data sources are read-only and used to build ARNs
# without hard-coding the account ID or partition name.
# ------------------------------------------------------

# Returns information about the current AWS caller (the account Terraform runs as)
# Useful for constructing ARNs like:
#   arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*
data "aws_caller_identity" "current" {}

# Returns the AWS partition name for the current environment:
#   - "aws"        for commercial regions
#   - "aws-cn"     for China regions
#   - "aws-us-gov" for GovCloud regions
# Using this avoids hard-coding "aws" in ARNs and keeps code portable.
data "aws_partition" "current" {}