# 🚖 RideBot — Technical Documentation

This document explains how the system is built and deployed: Terraform (AWS), Lambda (Python), API Gateway, DynamoDB, Amazon Location, SSM parameters, and CI/CD via GitHub Actions with OIDC.

---

## 📐 High-level architecture

```mermaid
graph TD
  TG[Telegram User] -->|Webhook updates| APIGW(API Gateway v2 – HTTP API)
  APIGW --> LBD[AWS Lambda (app.py)]
  LBD --> GEO[Amazon Location Service<br/>PlaceIndex & RouteCalculator]
  LBD --> DDB[(DynamoDB<br/>ridebot-trips)]
  LBD --> SSM[SSM Parameter Store<br/>/ridebot/*]
  LBD --> TGAPI[Telegram Bot API]

  subgraph IaC [Terraform]
    TF[Terraform] --> APIGW
    TF --> LBD
    TF --> DDB
    TF --> GEO
    TF --> SSM
    TF --> IAM[IAM Roles & Policies]
  end
```

---

## 📂 Repository structure

```
ridebot-infra/
├── docs/                # Documentation (this file, diagrams)
├── lambda_src/          # Python source code for Lambda (app.py, requirements.txt)
├── lambda_src.zip       # Packaged Lambda deployment artifact
├── terraform/           # IaC definitions
│   ├── apigw.tf         # API Gateway (HTTP API)
│   ├── backend.tf       # Remote backend (S3 + DynamoDB state/lock)
│   ├── dynamodb.tf      # DynamoDB table for trips
│   ├── iam.tf           # IAM roles & policies for Lambda
│   ├── identity.tf      # Caller identity & AWS partition data sources
│   ├── lambda.tf        # Lambda function definition & packaging
│   └── variables.tf     # Input variables (region, project name, etc.)
```

---

## ⚙️ Components

### **Lambda (Python)**
- Source: `lambda_src/app.py`
- Handles Telegram webhook events
- Calls:
  - DynamoDB (`ridebot-trips`) for storing trip requests
  - Amazon Location Service (search places, calculate routes)
  - SSM Parameter Store (`/ridebot/telegram_bot_token`) for secrets

### **API Gateway v2**
- Exposes a **public webhook URL** for Telegram to deliver updates.
- Integrates directly with the Lambda.

### **DynamoDB**
- Table: `ridebot-trips`
- Stores ride requests with partition key `ride_id` (string, UUID).

### **Amazon Location Service**
- `PlaceIndex` for address search.
- `RouteCalculator` for distance/ETA calculation.

### **SSM Parameter Store**
- Secrets stored securely:
  - `/ridebot/telegram_bot_token`
  - Any future configuration values.

### **IAM Roles & Policies**
- Least-privilege execution role for Lambda.
- GitHub Actions role with OIDC trust to deploy infra.

---

## 🚀 Deployment

### Local (manual)
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### GitHub Actions (CI/CD)
- Workflow: `.github/workflows/deploy.yml`
- Steps:
  1. Checkout repo
  2. Configure AWS creds via OIDC
  3. Terraform init/plan/apply

---

## ✅ Verifying webhook

After deploy, verify with:

```bash
TOKEN=$(aws ssm get-parameter --name /ridebot/telegram_bot_token --with-decryption --query 'Parameter.Value' --output text)
curl -s "https://api.telegram.org/bot${TOKEN}/getWebhookInfo"
```

Expected:
```json
{
  "ok": true,
  "result": {
    "url": "https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/telegram/webhook",
    "pending_update_count": 0
  }
}
```

---

## 🗂 DynamoDB Schema

| Attribute   | Type    | Notes                          |
|-------------|---------|--------------------------------|
| ride_id     | String  | Primary key (UUID)             |
| user_id     | String  | Telegram user ID               |
| pickup      | String  | Pickup address                 |
| dropoff     | String  | Dropoff address                |
| status      | String  | [requested, assigned, done]    |
| created_at  | String  | ISO timestamp                  |

Example item:
```json
{
  "ride_id": "123e4567-e89b-12d3-a456-426614174000",
  "user_id": "987654321",
  "pickup": "123 Main St, Navarre FL",
  "dropoff": "456 Gulf Breeze Pkwy, FL",
  "status": "requested",
  "created_at": "2025-09-20T12:00:00Z"
}
```

---

## 🔧 Troubleshooting

- **Webhook returns 404** → redeploy or check API Gateway URL matches Telegram webhook.
- **AccessDenied in Terraform** → ensure GitHub Actions role has required IAM permissions.
- **State lock issues** → check DynamoDB table used for Terraform state locks.

---

## 💰 Cost considerations

- **Lambda**: free tier covers 1M requests/month.
- **API Gateway**: ~$1 per million requests.
- **DynamoDB**: on-demand pricing; fits free tier for small usage.
- **Amazon Location**: free tier (2,500 requests/month), then pay-per-request.
- **SSM Parameter Store**: free for standard params.

---

© 2025 RideBot Infrastructure
