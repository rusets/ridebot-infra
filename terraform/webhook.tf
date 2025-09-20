# Build webhook URL from your HTTP API (v2) stage.
# If your stage resource is not "aws_apigatewayv2_stage.prod", replace it below.
locals {
  api_base    = trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")
  webhook_url = "${local.api_base}/telegram/webhook"
}

# 1) Set Telegram webhook on EVERY apply (force run).
# We do NOT reference other null_resources here to avoid undeclared-name errors.
resource "null_resource" "telegram_webhook" {
  triggers = {
    always_run  = timestamp()       # force on each apply
    webhook_url = local.webhook_url # also re-run when URL changes
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      # Read bot token from SSM with decryption at runtime (robust & local)
      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"

      # Delete old webhook (ignore errors)
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/deleteWebhook" \
        -d "drop_pending_updates=true" >/dev/null || true

      # Set new webhook to the CURRENT API URL
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" \
        -d "url=${local.webhook_url}" >/dev/null

      # Print current info (visible in terraform apply output)
      curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Wait until the HTTP API stage exists (rename if your stage has a different name)
  depends_on = [aws_apigatewayv2_stage.prod]
}

# 2) Verify with retries. If Telegram still shows old/empty URL, re-set and retry.
resource "null_resource" "telegram_webhook_verify" {
  triggers = {
    always_run = timestamp()        # run every apply
    expected   = local.webhook_url  # track expected URL
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"
      EXPECTED="${local.webhook_url}"

      # small grace period after setWebhook
      sleep 2

      for i in $(seq 1 12); do
        INFO="$(curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo" || true)"
        echo "getWebhookInfo attempt $i: $INFO" 1>&2

        # success if EXPECTED substring is present
        if printf "%s" "$INFO" | grep -q "$EXPECTED"; then
          echo "Webhook OK: $EXPECTED"
          exit 0
        fi

        echo "Webhook mismatch (want=$EXPECTED). Re-setting and retry $i..." 1>&2
        curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" \
          -d "url=$${EXPECTED}" >/dev/null || true
        sleep 3
      done

      echo "Failed to verify Telegram webhook after retries." >&2
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure API stage exists before verification (no dependency on other null_resources)
  depends_on = [aws_apigatewayv2_stage.prod]
}