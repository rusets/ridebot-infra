############################################
# Locals — Webhook URLs
# Purpose: build API base URL and Telegram webhook endpoint
############################################
locals {
  api_base    = trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")
  webhook_url = "${local.api_base}/telegram/webhook"
}

############################################
# Null Resource — Set Telegram Webhook
# Purpose: register the correct webhook URL
############################################
resource "null_resource" "telegram_webhook" {
  triggers = {
    always_run  = timestamp()
    webhook_url = local.webhook_url
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/deleteWebhook" -d "drop_pending_updates=true" >/dev/null || true
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" -d "url=${local.webhook_url}" >/dev/null
      curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_apigatewayv2_stage.prod]
}

############################################
# Null Resource — Verify Telegram Webhook
# Purpose: ensure webhook URL is correctly registered
############################################
resource "null_resource" "telegram_webhook_verify" {
  triggers = {
    always_run = timestamp()
    expected   = local.webhook_url
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"
      EXPECTED="${local.webhook_url}"
      sleep 2

      for i in $(seq 1 12); do
        INFO="$(curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo" || true)"
        if printf "%s" "$INFO" | grep -q "$EXPECTED"; then
          echo "Webhook OK: $EXPECTED"
          exit 0
        fi
        echo "Retry $i: resetting webhook..."
        curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" -d "url=$${EXPECTED}" >/dev/null || true
        sleep 3
      done

      echo "Failed to verify Telegram webhook after retries." >&2
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [aws_apigatewayv2_stage.prod]
}
