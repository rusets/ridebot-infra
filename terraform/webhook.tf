# ------------------------------------------------------
# Local values: build API base URL and final webhook URL
# ------------------------------------------------------
locals {
  # Base URL of the API Gateway stage (strip trailing "/")
  api_base = trimsuffix(aws_apigatewayv2_stage.prod.invoke_url, "/")

  # Full Telegram webhook endpoint (POST /telegram/webhook)
  webhook_url = "${local.api_base}/telegram/webhook"
}

# ------------------------------------------------------
# Resource 1: Set Telegram webhook
# ------------------------------------------------------
# Runs a local script during `terraform apply` to register the
# correct webhook URL in Telegram.
# - Uses null_resource + local-exec so it is executed each time.
# - Deletes old webhook (if any), then sets new one.
# - Prints current webhook info to Terraform logs.
resource "null_resource" "telegram_webhook" {
  # Triggers:
  # - always_run ensures it executes on every `apply`
  # - webhook_url ensures re-run when URL changes
  triggers = {
    always_run  = timestamp()
    webhook_url = local.webhook_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      # Fetch bot token from SSM Parameter Store (decrypted at runtime)
      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"

      # Remove old webhook to avoid mismatches (ignore errors if none exists)
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/deleteWebhook" \
        -d "drop_pending_updates=true" >/dev/null || true

      # Register the new webhook pointing to the CURRENT API URL
      curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" \
        -d "url=${local.webhook_url}" >/dev/null

      # Print current webhook info for visibility in terraform output
      curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure API Gateway stage exists before setting webhook
  depends_on = [aws_apigatewayv2_stage.prod]
}

# ------------------------------------------------------
# Resource 2: Verify Telegram webhook
# ------------------------------------------------------
# Adds an extra verification step after setting webhook.
# - Repeatedly queries getWebhookInfo
# - If Telegram does not report the expected URL, retries setWebhook.
# - Fails after max retries if still not correct.
resource "null_resource" "telegram_webhook_verify" {
  triggers = {
    always_run = timestamp()
    expected   = local.webhook_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      TOKEN="$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)"
      EXPECTED="${local.webhook_url}"

      # Give Telegram API a small grace period before checks
      sleep 2

      for i in $(seq 1 12); do
        INFO="$(curl -s "https://api.telegram.org/bot$${TOKEN}/getWebhookInfo" || true)"
        echo "getWebhookInfo attempt $i: $INFO" 1>&2

        # Success: webhook URL matches what we expect
        if printf "%s" "$INFO" | grep -q "$EXPECTED"; then
          echo "Webhook OK: $EXPECTED"
          exit 0
        fi

        # Otherwise, retry by re-sending setWebhook
        echo "Webhook mismatch (want=$EXPECTED). Re-setting and retry $i..." 1>&2
        curl -s -X POST "https://api.telegram.org/bot$${TOKEN}/setWebhook" \
          -d "url=$${EXPECTED}" >/dev/null || true
        sleep 3
      done

      # Fail if still wrong after all retries
      echo "Failed to verify Telegram webhook after retries." >&2
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # Ensure API stage exists before verification
  depends_on = [aws_apigatewayv2_stage.prod]
}