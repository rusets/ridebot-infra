# Read Telegram bot token as decrypted SecureString
data "aws_ssm_parameter" "telegram_token" {
  name            = "/ridebot/telegram_bot_token"
  with_decryption = true
}

data "aws_ssm_parameter" "driver_chat_id" {
  name            = var.ssm_driver_chat_id_name
  with_decryption = false
}
