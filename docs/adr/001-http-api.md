# ADR-001 — Use API Gateway HTTP API v2 Instead of REST API v1
**Status:** Accepted  
**Date:** 2025-12-06  

---

## Context
Ridebot requires a public HTTPS endpoint for Telegram Webhook. AWS offers two options:
- API Gateway REST API v1  
- API Gateway HTTP API v2

REST API provides more features but is more expensive and slower for a simple webhook.

---

## Decision
Use **API Gateway v2 (HTTP API)** for the webhook endpoint.

---

## Rationale
- ~60% cheaper per request  
- Faster cold starts for Lambda proxy integration  
- Lightweight routing and setup  
- Zero mapping templates required  
- Ideal for webhook-style POST handlers

---

## Consequences
- No API keys / usage plans (not required here)  
- Some legacy integrations unsupported (irrelevant for this project)