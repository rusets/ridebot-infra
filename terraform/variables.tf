# ------------------------------------------------------
# Terraform Variables
# Centralized configuration for project-wide settings.
# ------------------------------------------------------

# AWS region where all resources will be deployed.
# Default is us-east-1, which is required for some global services (e.g., API Gateway edge-optimized).
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# Project name prefix.
# Used to make resource names unique (e.g., ridebot-trips, ridebot-places).
variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "ridebot"
}

# Name of the SSM Parameter that stores the Telegram Bot Token.
# This must be created manually in AWS Systems Manager Parameter Store.
# IMPORTANT:
# - Store as SecureString.
# - This way the token never appears in Terraform state or code.
variable "ssm_telegram_token_name" {
  description = "SSM Parameter name that stores TELEGRAM_BOT_TOKEN (SecureString)"
  type        = string
  default     = "/ridebot/telegram_bot_token"
}

# Name of the SSM Parameter that stores the driver’s Telegram Chat ID.
# This is just a numeric user ID (not sensitive), so stored as plain String.
# Allows bot to send trip notifications directly to driver(s).
variable "ssm_driver_chat_id_name" {
  description = "SSM Parameter name that stores DRIVER_CHAT_ID (String)"
  type        = string
  default     = "/ridebot/driver_chat_id"
}

# DynamoDB billing mode:
# - PAY_PER_REQUEST → Scales automatically, no need to manage capacity.
# - PROVISIONED    → You can set small RCUs/WCUs to fit AWS Free Tier,
#                    but you must adjust manually if traffic increases.
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode. Use PAY_PER_REQUEST for simplicity. To leverage Always Free, switch to PROVISIONED with small RCUs/WCUs."
  type        = string
  default     = "PAY_PER_REQUEST"
}