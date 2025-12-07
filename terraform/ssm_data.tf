############################################
# Data — SSM Parameters
# Purpose: read bot token and driver chat ID
############################################
data "aws_ssm_parameter" "telegram_token" {
  name            = var.ssm_telegram_token_name
  with_decryption = true
}

data "aws_ssm_parameter" "driver_chat_id" {
  name            = var.ssm_driver_chat_id_name
  with_decryption = false
}
