############################################
# Terraform — Variables
# Purpose: global project configuration
############################################
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "ridebot"
}

variable "ssm_telegram_token_name" {
  description = "SSM Parameter name for TELEGRAM_BOT_TOKEN (SecureString)"
  type        = string
  default     = "/ridebot/telegram_bot_token"
}

variable "ssm_driver_chat_id_name" {
  description = "SSM Parameter name for DRIVER_CHAT_ID (String)"
  type        = string
  default     = "/ridebot/driver_chat_id"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
}
