# Ridebot — Current Limitations

---

## 1. No SMS Gateway Integration
Driver contacts the client manually.  
No automated SMS via SNS/Twilio.

**Impact:** Manual workflow for driver notifications.

---

## 2. No Driver GPS Tracking
Drivers cannot share real-time location or ETA.

**Impact:** Limited transparency for users.

---

## 3. No Dispatch Algorithm
Requests are sent to all drivers simultaneously.  
First driver to accept wins.

**Impact:** No load balancing or fairness logic.

---

## 4. Address Accuracy Depends on Amazon Location
Geocoding may require more precise input in rural areas.

**Impact:** Occasional need for manual corrections.

---

## 5. No Admin Dashboard
Trip history and driver activity visible only through AWS Console or DynamoDB queries.

**Impact:** Limited visibility for business operations.

---

## 6. No Payment Gateway
Only manual payments (cash, Zelle, Venmo).  
No Stripe/PayPal integration.

**Impact:** No automated receipts or prepayments.

---

## 7. Lambda Cold Starts After Idle Period
Python Lambda has small but noticeable cold-start delay.

**Impact:** First request may be slower (200–700 ms).

---

## 8. Telegram Is Single Point of Interaction
System depends fully on Telegram availability.

**Impact:** No fallback (SMS or web form).