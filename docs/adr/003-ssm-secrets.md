# ADR-003 — Store Secrets in SSM Parameter Store
**Status:** Accepted  
**Date:** 2025-12-06  

---

## Context
Sensitive values (Telegram bot token, driver IDs) must be stored securely and must not appear in:
- Git  
- Terraform configuration  
- Terraform state

---

## Decision
Use **AWS Systems Manager Parameter Store** for secrets:
- `/ridebot/telegram_bot_token` (SecureString)  
- `/ridebot/driver_chat_ids` (String)

Lambda reads values at runtime.

---

## Rationale
- Centralized secret storage  
- IAM-controlled access  
- Encrypted at rest via KMS  
- Terraform does not expose any secret in state  
- Safe for public GitHub repositories

---

## Consequences
- Parameters must be created/updated separately from Terraform  
- Missing permissions will break Lambda initialization