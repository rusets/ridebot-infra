# ------------------------------------------------------
# AWS Systems Manager (SSM) Parameter Store
# Used for storing and retrieving secrets and configuration values.
# ------------------------------------------------------

# Telegram bot token (stored as SecureString in SSM Parameter Store)
# - Path: /ridebot/telegram_bot_token
# - with_decryption = true → Terraform can read the decrypted value
#   so that Lambda environment can use it securely.
data "aws_ssm_parameter" "telegram_token" {
  name            = "/ridebot/telegram_bot_token"
  with_decryption = true
}

# Driver chat ID(s) for Telegram
# - Passed via variable (allows multiple drivers or different environments)
# - Not encrypted, since it's not sensitive (just a numeric Telegram user ID)
data "aws_ssm_parameter" "driver_chat_id" {
  name            = var.ssm_driver_chat_id_name
  with_decryption = false
}