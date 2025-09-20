terraform {
  backend "s3" {
    bucket         = "ridebot-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ridebot-tf-locks"  # ← это имя
    encrypt        = true
  }
}