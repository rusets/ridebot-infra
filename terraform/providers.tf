############################################
# Provider — AWS
# Purpose: define region and authentication
############################################
provider "aws" {
  region = var.aws_region
}

############################################
# Terraform Settings & Provider Requirements
############################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}
