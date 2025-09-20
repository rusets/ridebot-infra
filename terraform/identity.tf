# Who am I? (account id)
data "aws_caller_identity" "current" {}

# (опционально, если где-то нужно) aws partition: aws / aws-cn / aws-us-gov
data "aws_partition" "current" {}
