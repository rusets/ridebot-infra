plugin "aws" {
  enabled = true
  version = "0.34.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  module = false
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true

  # naming rules
  variable          = "^[a-z][a-z0-9_]*$"
  resource          = "^[a-z][a-z0-9_]*$"
  module            = "^[a-z][a-z0-9_]*$"
  output            = "^[a-z][a-z0-9_]*$"
  locals            = "^[a-z][a-z0-9_]*$"
}

aws {
  region = "us-east-1"
}

# Ignore rules that conflict with serverless/managed services
rule "aws_dynamodb_table_invalid_ttl_specification" {
  enabled = false
}