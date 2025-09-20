# ------------------------------------------------------
# AWS Provider configuration
# This tells Terraform to use AWS as the infrastructure provider.
# ------------------------------------------------------
provider "aws" {
  # AWS region to deploy all resources into
  # Example: us-east-1
  region = var.aws_region

  # Authentication details:
  # - In GitHub Actions → Terraform authenticates via OIDC and IAM role
  # - Locally (developer machine) → Terraform uses AWS CLI profile
  #   or environment variables (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
}