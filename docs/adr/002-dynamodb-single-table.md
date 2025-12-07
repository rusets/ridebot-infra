# ADR-002 — Use DynamoDB Single-Table Schema
**Status:** Accepted  
**Date:** 2025-12-06  

---

## Context
Ridebot stores multiple related entities:
- users  
- trips  
- sessions  
- driver actions  

A scalable low-latency storage layer is required.

---

## Decision
Implement a **single-table design** using:
- `pk` — partition key (e.g., USER#id, TRIP#id)  
- `sk` — sort key (metadata and sub-records)

---

## Rationale
- Fast queries using prefix patterns  
- Minimal read/write operations  
- Perfect for Telegram chat bots with unpredictable traffic  
- PAY_PER_REQUEST billing simplifies cost control  
- Flexible structure for new item types

---

## Consequences
- Requires naming conventions and strict key patterns  
- Must avoid schema drift in application code