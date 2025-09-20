# ------------------------------------------------------
# Terraform Settings & Provider Requirements
# ------------------------------------------------------
terraform {
  # Require Terraform CLI version 1.5.0 or newer.
  # This ensures compatibility with features like improved for_each, moved blocks, etc.
  required_version = ">= 1.5.0"

  # Declare all providers used in this project with pinned versions.
  # Pinning avoids unexpected breaking changes when providers release new versions.
  required_providers {
    # AWS provider (manages all AWS resources).
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0" # stable, supports latest AWS features
    }

    # Archive provider (used to package Lambda source code into ZIP before upload).
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }

    # Random provider (can generate random strings/secrets if needed).
    # Not currently used, but helpful for unique names or test data.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}