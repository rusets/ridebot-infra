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

# Names of SSM parameters that you will create yourself (so secrets never land in TF state)
variable "ssm_telegram_token_name" {
  description = "SSM Parameter name that stores TELEGRAM_BOT_TOKEN (SecureString)"
  type        = string
  default     = "/ridebot/telegram_bot_token"
}

variable "ssm_driver_chat_id_name" {
  description = "SSM Parameter name that stores DRIVER_CHAT_ID (String)"
  type        = string
  default     = "/ridebot/driver_chat_id"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode. Use PAY_PER_REQUEST for simplicity. To leverage Always Free, switch to PROVISIONED with small RCUs/WCUs."
  type        = string
  default     = "PAY_PER_REQUEST"
}
