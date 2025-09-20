# RideBot — AWS Serverless MVP (Telegram + Lambda + API Gateway + DynamoDB + Amazon Location)

## What you'll deploy
- Telegram bot webhook via **API Gateway (HTTP API)** → **AWS Lambda (Python 3.12)**
- Data in **DynamoDB** (single-table: sessions + trips)
- Routing, ETA and geocoding via **Amazon Location Service** (Here provider)
- Secrets in **SSM Parameter Store** (NO secrets in Terraform state)
- Logs & metrics in **CloudWatch**

---

## 0) Prereqs
- AWS CLI v2 authenticated for the right account/region.
- Terraform >= 1.5.
- A Telegram bot token from **@BotFather**.
- Your Telegram **driver** chat id (e.g., from @userinfobot).

---

## 1) Create SSM parameters (outside of Terraform)
```bash
aws ssm put-parameter --name "/ridebot/telegram_bot_token" --type "SecureString" --value "123456:ABCDEF" --overwrite
aws ssm put-parameter --name "/ridebot/driver_chat_id"     --type "String"       --value "123456789" --overwrite
```

> Using SSM keeps secrets **out of Terraform state**. Terraform only references names/ARNs.

---

## 2) Deploy Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Outputs will include:
- `api_base_url`
- `webhook_url`
- `dynamodb_table`
- `place_index_name`
- `route_calculator_name`

---

## 3) Set Telegram webhook
```bash
TOKEN=$(aws ssm get-parameter --name "/ridebot/telegram_bot_token" --with-decryption --query Parameter.Value --output text)
WEBHOOK="$(terraform output -raw webhook_url)"
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/setWebhook" -d "url=${WEBHOOK}"
```

Test:
- Open Telegram, send `/start` to your bot.
- Send `Заказать`, then addresses (pickup then dropoff).
- Confirm price or offer your price.
- Driver receives actions in his chat (based on DRIVER_CHAT_ID).

---

## 4) Fare tweaks (no redeploy needed)
Adjust environment variables in Lambda console (Configuration → Environment):
- `FARE_BASE`, `FARE_PER_MILE`, `FARE_PER_MIN`, `FARE_FEE`, `FARE_SURGE`, `FARE_MINIMUM`

---

## Notes
- DynamoDB table billing is **PAY_PER_REQUEST** for simplicity. To leverage Always Free, you may switch to **PROVISIONED** with small RCUs/WCUs.
- Amazon Location uses **Here** data provider. You can switch to **Esri** if preferred.
- All code is in `lambda_src/app.py`. Packaging is handled by `archive_file` data source.
- API path is `/telegram/webhook` and accepts **POST** from Telegram.

---

## Clean up
```bash
terraform destroy
```
