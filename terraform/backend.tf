terraform {
  backend "s3" {
    # S3 bucket name for storing Terraform state file
    bucket = "ridebot-terraform-state"

    # Path (key) inside the bucket — acts like a file path
    key = "global/terraform.tfstate"

    # AWS region where the S3 bucket and DynamoDB table exist
    region = "us-east-1"

    # DynamoDB table name for state locking and consistency
    # Prevents two users/pipelines from applying changes at the same time
    dynamodb_table = "ridebot-tf-locks"

    # Enable encryption at rest for the state file in S3
    encrypt = true
  }
}