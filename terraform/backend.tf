############################################
# Terraform Backend — Remote State Configuration
# Purpose: store state securely in S3 with DynamoDB lock
############################################
terraform {
  backend "s3" {
    bucket         = "ridebot-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ridebot-tf-locks"
    encrypt        = true
  }
}
