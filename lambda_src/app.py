import os
import json
import logging
import base64
import random
import string
import time
import re
from decimal import Decimal
from datetime import datetime, timedelta, date

import boto3
from boto3.dynamodb.conditions import Key
import urllib.request
import urllib.parse
from zoneinfo import ZoneInfo

# ---------- Logging ----------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------- AWS clients ----------
ssm = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")
location = boto3.client("location")

# ---------- Environment ----------
TABLE_NAME = os.environ["TABLE_NAME"]
PLACE_INDEX_NAME = os.environ["PLACE_INDEX_NAME"]
ROUTE_CALCULATOR_NAME = os.environ["ROUTE_CALCULATOR_NAME"]

# All user-facing date/time is displayed in this timezone
TZ = ZoneInfo(os.environ.get("TIMEZONE", "America/Chicago"))

# Number of days to show in the inline date picker (starting from today)
DAYS_AHEAD = int(os.environ.get("PICKER_DAYS_AHEAD", "5"))

# Fare settings
FARE_BASE = float(os.environ.get("FARE_BASE", "3.00"))
FARE_PER_MILE = float(os.environ.get("FARE_PER_MILE", "2.50"))
FARE_PER_MIN = float(os.environ.get("FARE_PER_MIN", "0.40"))
FARE_FEE = float(os.environ.get("FARE_FEE",  "1.00"))
FARE_MINIMUM = float(os.environ.get("FARE_MINIMUM", "8.00"))

# Short-trip rule: if distance < threshold, apply minimum fare
SHORT_TRIP_MILES_THRESHOLD = float(
    os.environ.get("SHORT_TRIP_MILES_THRESHOLD", "5.0"))
SHORT_TRIP_MINIMUM = float(os.environ.get("SHORT_TRIP_MINIMUM", "10.0"))

# ---------- Secrets (Telegram + drivers) ----------
_TELEGRAM_TOKEN = None
_DRIVER_CHAT_IDS = None              # list[str]
_DRIVER_PROFILES = None              # dict[str, {"name": "...", "car": "..."}]


def _get_secret(name, decrypt=True):
    return ssm.get_parameter(Name=name, WithDecryption=decrypt)["Parameter"]["Value"]


def ensure_secrets():
    """Load Telegram token, driver chat IDs list, and driver profiles JSON from SSM."""
    global _TELEGRAM_TOKEN, _DRIVER_CHAT_IDS, _DRIVER_PROFILES
    if _TELEGRAM_TOKEN is None:
        _TELEGRAM_TOKEN = _get_secret("/ridebot/telegram_bot_token", True)
    if _DRIVER_CHAT_IDS is None:
        try:
            raw = _get_secret("/ridebot/driver_chat_ids", False)
            _DRIVER_CHAT_IDS = [x.strip() for x in raw.split(",") if x.strip()]
        except Exception:
            _DRIVER_CHAT_IDS = []
    if _DRIVER_PROFILES is None:
        try:
            prof_raw = _get_secret("/ridebot/driver_profiles", False)
            _DRIVER_PROFILES = json.loads(prof_raw)
        except Exception:
            _DRIVER_PROFILES = {}


# ---------- Resources ----------
table = dynamodb.Table(TABLE_NAME)

# ---------- Utilities ----------


def ddb_decimalize(obj):
    """Convert floats to Decimal recursively to satisfy DynamoDB types."""
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: ddb_decimalize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [ddb_decimalize(v) for v in obj]
    return obj


def now_ts() -> int:
    """Epoch seconds in local TZ (for consistency in storage)."""
    return int(datetime.now(TZ).timestamp())


def round_to_15m(dt: datetime) -> datetime:
    """Round a datetime up to the next 15-minute increment."""
    minutes = (dt.minute + 14) // 15 * 15
    if minutes == 60:
        dt = dt.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
    else:
        dt = dt.replace(minute=minutes, second=0, microsecond=0)
    return dt


def fmt_ampm(dt: datetime) -> str:
    """Format datetime as 12-hour time like '6:30 PM' (local TZ)."""
    return dt.astimezone(TZ).strftime("%I:%M %p").lstrip("0")


def fmt_epoch_ampm(epoch: int) -> str:
    return fmt_ampm(datetime.fromtimestamp(int(epoch), TZ))


def normalize_phone(text):
    """Normalize phone to E.164 where possible; default country code +1 if 10 digits."""
    if not text:
        return None
    digits = re.sub(r"[^\d+]", "", text.strip())
    if digits.startswith("+") and re.fullmatch(r"\+\d{8,15}", digits):
        return digits
    only = re.sub(r"\D", "", digits)
    if re.fullmatch(r"\d{10}", only):
        return "+1" + only
    if re.fullmatch(r"1\d{10}", only):
        return "+" + only
    return None


# Date/time parsing helpers (optional manual input support)
DATE_YMD = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
DATE_MDY = re.compile(r"^(\d{1,2})/(\d{1,2})/(\d{4})$")
TIME_HM_24 = re.compile(r"^(\d{1,2}):(\d{2})$")
TIME_HM_AMPM = re.compile(
    r"^(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)$", re.IGNORECASE)


def _to_24h(h, m, ampm):
    h = int(h)
    m = int(m)
    ampm = ampm.lower().replace(".", "")
    if ampm == "pm" and h != 12:
        h += 12
    if ampm == "am" and h == 12:
        h = 0
    return h, m


def parse_when(text):
    """Parse strings like 'today 6pm' / '2025-09-21 2:30 PM' -> (iso_text, epoch) or (None, None)."""
    t = " ".join(text.strip().split())
    if not t:
        return (None, None)
    now_local = datetime.now(TZ)

    def finish(dt):
        dt = round_to_15m(dt)
        return dt.strftime("%Y-%m-%d %H:%M"), int(dt.timestamp())

    m = re.match(
        r"^(today|tomorrow)\s+(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)$", t, re.IGNORECASE)
    if m:
        base = now_local.date() if m.group(1).lower() == "today" else (
            now_local + timedelta(days=1)).date()
        h, mm = m.group(2), m.group(3) or "00"
        h24, m24 = _to_24h(h, mm, m.group(4))
        try:
            return finish(datetime(base.year, base.month, base.day, h24, m24, tzinfo=TZ))
        except:
            return (None, None)

    m = re.match(
        r"^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)$", t, re.IGNORECASE)
    if m:
        h24, m24 = _to_24h(m.group(4), m.group(5) or "00", m.group(6))
        try:
            return finish(datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), h24, m24, tzinfo=TZ))
        except:
            return (None, None)

    m = re.match(
        r"^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)$", t, re.IGNORECASE)
    if m:
        h24, m24 = _to_24h(m.group(4), m.group(5) or "00", m.group(6))
        try:
            return finish(datetime(int(m.group(3)), int(m.group(1)), int(m.group(2)), h24, m24, tzinfo=TZ))
        except:
            return (None, None)

    return (None, None)


def parse_date_only(text):
    t = text.strip().lower()
    now_local = datetime.now(TZ)
    if t == "today":
        d = now_local.date()
        return d.year, d.month, d.day
    if t == "tomorrow":
        d = (now_local + timedelta(days=1)).date()
        return d.year, d.month, d.day
    m = DATE_YMD.match(t)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    m = DATE_MDY.match(t)
    if m:
        return int(m.group(3)), int(m.group(1)), int(m.group(2))
    return None


def parse_time_only(text):
    t = text.strip().lower().replace(" ", "")
    m = re.match(r"^(\d{1,2})([ap]m)$", t)
    if m:
        h24, m24 = _to_24h(m.group(1), 0, m.group(2))
        return h24, m24
    m = TIME_HM_AMPM.match(text.strip())
    if m:
        h24, m24 = _to_24h(m.group(1), m.group(2) or "00", m.group(3))
        return h24, m24
    m = TIME_HM_24.match(text.strip())
    if m:
        hh, mm = int(m.group(1)), int(m.group(2))
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            return hh, mm
    return None


def combine_date_time(y, m, d, hh, mm):
    dt = round_to_15m(datetime(y, m, d, hh, mm, tzinfo=TZ))
    return dt.strftime("%Y-%m-%d %H:%M"), int(dt.timestamp())

# ---------- Inline date/time picker ----------


def build_date_buttons(trip_id, days_ahead=DAYS_AHEAD):
    """Build date buttons starting from 'Today' for the next N days."""
    today_local = datetime.now(TZ).date()
    rows = []
    for i in range(days_ahead):
        d = today_local + timedelta(days=i)
        label = ("Today, " if i == 0 else "") + d.strftime("%a, %b %d")
        rows.append(
            [{"text": label, "callback_data": f"datepick:{trip_id}:{d.isoformat()}"}])
    return rows


def build_time_buttons(trip_id, y, m, d):
    """Time slots from 6:00 AM to 12:00 AM (midnight) every 30 minutes."""
    rows = []
    start = datetime(y, m, d, 6, 0, tzinfo=TZ)
    end = datetime(y, m, d, 23, 59, tzinfo=TZ)
    cur = start
    while cur <= end:
        label = fmt_ampm(cur)
        epoch = int(cur.timestamp())
        rows.append(
            [{"text": label, "callback_data": f"timepick:{trip_id}:{epoch}"}])
        cur += timedelta(minutes=30)
    if not rows:
        rows.append(
            [{"text": "No times available", "callback_data": f"datesel:{trip_id}"}])
    return rows

# ---------- Telegram helpers ----------


def tg_request(method, fields):
    ensure_secrets()
    url = f"https://api.telegram.org/bot{_TELEGRAM_TOKEN}/{method}"
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={
                                 "Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read().decode("utf-8")
        try:
            return json.loads(raw)
        except:
            return {"ok": True}


def tg_send_message(chat_id, text, buttons=None, reply_kb=None):
    payload = {"chat_id": str(chat_id), "text": text}
    if buttons:
        payload["reply_markup"] = json.dumps({"inline_keyboard": buttons})
    if reply_kb:
        payload["reply_markup"] = json.dumps(
            {"keyboard": reply_kb, "resize_keyboard": True, "one_time_keyboard": False})
    return tg_request("sendMessage", payload)


def tg_edit_text(chat_id, message_id, text, clear_keyboard=False):
    payload = {"chat_id": str(chat_id), "message_id": int(
        message_id), "text": text}
    if clear_keyboard:
        payload["reply_markup"] = json.dumps({"inline_keyboard": []})
    return tg_request("editMessageText", payload)


def tg_edit_reply_markup_clear(chat_id, message_id):
    payload = {"chat_id": str(chat_id), "message_id": int(
        message_id), "reply_markup": json.dumps({"inline_keyboard": []})}
    return tg_request("editMessageReplyMarkup", payload)


def tg_set_commands():
    cmds = [
        {"command": "start", "description": "Open menu"},
        {"command": "menu", "description": "Open menu"},
        {"command": "newride", "description": "Start a new ride"},
        {"command": "mytrips", "description": "Show recent trips"},
        {"command": "help", "description": "How it works"},
    ]
    return tg_request("setMyCommands", {"commands": json.dumps(cmds)})

# ---------- AWS Location / Fare ----------


def calc_fare(miles, minutes):
    fare = FARE_BASE + (miles * FARE_PER_MILE) + \
        (minutes * FARE_PER_MIN) + FARE_FEE
    fare = max(fare, FARE_MINIMUM)
    if miles < SHORT_TRIP_MILES_THRESHOLD:
        fare = max(fare, SHORT_TRIP_MINIMUM)
    return round(fare, 2)


def geocode_once(text):
    """Geocode address text once; fall back to adding 'FL, USA' hint if needed."""
    try:
        def _search(q):
            return location.search_place_index_for_text(
                IndexName=PLACE_INDEX_NAME, Text=q, MaxResults=1,
                FilterCountries=["USA"], Language="en"
            )
        r = _search(text)
        results = r.get("Results", [])
        if not results:
            r = _search(f"{text}, FL, USA")
            results = r.get("Results", [])
        if not results:
            return None
        p = results[0]["Place"]
        label = p.get("Label", text)
        lon, lat = map(float, p["Geometry"]["Point"])
        return {"label": label, "lon": lon, "lat": lat}
    except Exception:
        return None


def calc_route(dep, dest):
    """Return (distance_meters, duration_seconds) using Amazon Location routes."""
    try:
        r = location.calculate_route(
            CalculatorName=ROUTE_CALCULATOR_NAME,
            DeparturePosition=[dep["lon"], dep["lat"]],
            DestinationPosition=[dest["lon"], dest["lat"]],
            TravelMode="Car"
        )
        s = r["Summary"]
        return int(float(s["Distance"]) * 1000.0), int(float(s["DurationSeconds"]))
    except Exception:
        return None, None

# ---------- Sessions & Profile ----------


def get_session(user_id):
    resp = table.get_item(Key={"pk": f"USER#{user_id}", "sk": "SESSION"})
    return resp.get("Item")


def put_session(user_id, state, data=None):
    table.put_item(Item={"pk": f"USER#{user_id}",
                   "sk": "SESSION", "state": state, "data": data or {}})


def clear_session(user_id):
    table.delete_item(Key={"pk": f"USER#{user_id}", "sk": "SESSION"})


def get_profile(user_id):
    resp = table.get_item(Key={"pk": f"USER#{user_id}", "sk": "PROFILE"})
    return resp.get("Item")


def set_profile_phone(user_id, phone):
    table.put_item(Item={"pk": f"USER#{user_id}",
                   "sk": "PROFILE", "phone": phone, "updated_at": now_ts()})

# ---------- Trips ----------


def save_trip(user_id, dep, dest, miles, minutes, fare):
    tid = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
    created = now_ts()
    dep_ddb = ddb_decimalize(dep)
    dest_ddb = ddb_decimalize(dest)
    table.put_item(Item={
        "pk": f"USER#{user_id}", "sk": f"TRIP#{tid}",
        "trip_id": tid, "user_id": str(user_id),
        "dep": dep_ddb, "dest": dest_ddb,
        "miles": Decimal(str(miles)), "minutes": Decimal(str(minutes)),
        "fare": Decimal(str(fare)), "status": "await_when", "created_at": created
    })
    table.put_item(Item={
        "pk": f"TRIP#{tid}", "sk": "META",
        "trip_id": tid, "user_id": str(user_id), "user_chat_id": str(user_id),
        "dep_label": dep.get("label", ""), "dest_label": dest.get("label", ""),
        "miles": Decimal(str(miles)), "minutes": Decimal(str(minutes)),
        "fare": Decimal(str(fare)), "status": "await_when", "created_at": created
    })
    return tid


def set_trip_when_epoch(trip_id, epoch):
    dt = round_to_15m(datetime.fromtimestamp(int(epoch), TZ))
    iso = dt.strftime("%Y-%m-%d %H:%M")
    table.update_item(
        Key={"pk": f"TRIP#{trip_id}", "sk": "META"},
        UpdateExpression="SET desired_time_text=:t, desired_time_epoch=:e",
        ExpressionAttributeValues={":t": iso, ":e": int(dt.timestamp())}
    )


def set_trip_when(trip_id, when_text, when_epoch):
    table.update_item(
        Key={"pk": f"TRIP#{trip_id}", "sk": "META"},
        UpdateExpression="SET desired_time_text=:t, desired_time_epoch=:e",
        ExpressionAttributeValues={":t": when_text, ":e": int(when_epoch)}
    )


def set_trip_phone(trip_id, phone_e164):
    table.update_item(
        Key={"pk": f"TRIP#{trip_id}", "sk": "META"},
        UpdateExpression="SET passenger_phone=:p",
        ExpressionAttributeValues={":p": phone_e164}
    )


def set_trip_status(trip_id, user_id, status):
    table.update_item(
        Key={"pk": f"TRIP#{trip_id}", "sk": "META"},
        UpdateExpression="SET #s=:s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": status}
    )
    table.update_item(
        Key={"pk": f"USER#{user_id}", "sk": f"TRIP#{trip_id}"},
        UpdateExpression="SET #s=:s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": status}
    )


def set_trip_driver(trip_id, driver_id, driver_name, driver_car):
    table.update_item(
        Key={"pk": f"TRIP#{trip_id}", "sk": "META"},
        UpdateExpression="SET driver_id=:d, driver_name=:n, driver_car=:c",
        ExpressionAttributeValues={
            ":d": str(driver_id), ":n": driver_name, ":c": driver_car}
    )


def get_trip_meta(trip_id):
    resp = table.get_item(Key={"pk": f"TRIP#{trip_id}", "sk": "META"})
    return resp.get("Item")


def list_recent_trips(chat_id, user_id):
    resp = table.query(
        KeyConditionExpression=Key("pk").eq(
            f"USER#{user_id}") & Key("sk").begins_with("TRIP#"),
        ScanIndexForward=False, Limit=5
    )
    items = resp.get("Items", [])
    if not items:
        tg_send_message(chat_id, "You have no trips yet.")
        return
    lines = []
    for it in items:
        dep = it.get("dep", {}).get("label", "—")
        dest = it.get("dest", {}).get("label", "—")
        miles = float(it.get("miles", 0))
        mins = int(float(it.get("minutes", 0)))
        fare = float(it.get("fare", 0))
        tid = it.get("trip_id", "—")
        status = it.get("status", "unknown")
        when = it.get("desired_time_text", "—")
        dname = it.get("driver_name", "—")
        dcar = it.get("driver_car", "")
        lines.append(
            f"#{tid}: {dep} → {dest}\n  {miles:.1f} mi • {mins} min • ${fare:.2f} • {status} • {when} • {dname} {dcar}".strip())
    tg_send_message(chat_id, "Your recent trips:\n\n" + "\n\n".join(lines))


# ---------- Menu ----------
MAIN_MENU = [["📝 New ride", "🚖 My trips"], ["⚙️ Settings", "ℹ️ Help"]]


def show_menu(chat_id): tg_send_message(
    chat_id, "Choose an action:", reply_kb=MAIN_MENU)

# ---------- Lambda entry ----------


def lambda_handler(event, context):
    try:
        body = event.get("body", "")
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode("utf-8")
        update = json.loads(body or "{}")
    except Exception:
        logger.exception("Failed to parse body")
        return {"statusCode": 200, "body": "ok"}

    # --- Message flow ---
    if "message" in update:
        msg = update["message"]
        chat_id = msg["chat"]["id"]
        user_id = msg["from"]["id"]
        text = (msg.get("text") or "").strip()

        if text in ("/start", "/menu"):
            clear_session(user_id)
            tg_set_commands()
            tg_send_message(
                chat_id, "Hello! I’m your ride assistant.", reply_kb=MAIN_MENU)
            put_session(user_id, "idle", {})
            return {"statusCode": 200, "body": "ok"}

        if text in ("/newride", "📝 New ride"):
            clear_session(user_id)
            tg_send_message(chat_id, "Please enter the pickup address.")
            put_session(user_id, "await_pickup", {})
            return {"statusCode": 200, "body": "ok"}

        if text in ("/mytrips", "🚖 My trips"):
            list_recent_trips(chat_id, user_id)
            show_menu(chat_id)
            return {"statusCode": 200, "body": "ok"}

        if text in ("/help", "ℹ️ Help"):
            show_menu(chat_id)
            tg_send_message(
                chat_id,
                "Flow:\n1) Pickup & drop-off\n2) Pick date & time\n"
                "3) Enter phone (saved for next time)\n4) Confirm — driver will contact you via SMS."
            )
            return {"statusCode": 200, "body": "ok"}

        session = get_session(user_id) or {}
        state = session.get("state")
        sdata = session.get("data", {}) or {}

        # We enforce date/time picking via inline picker only
        if state and isinstance(state, str) and state.startswith("await_when:"):
            tg_send_message(chat_id, "Please use 📆 Pick date & time.")
            return {"statusCode": 200, "body": "ok"}

        if state in ("await_time", "await_date"):
            tg_send_message(chat_id, "Please use 📆 Pick date & time.")
            return {"statusCode": 200, "body": "ok"}

        # Phone entry
        if state and isinstance(state, str) and state.startswith("await_phone:"):
            trip_id = state.split(":", 1)[1]
            phone = normalize_phone(text)
            if not phone:
                tg_send_message(
                    chat_id, "Phone format is invalid. Please enter like +1 850 555 1234.")
                return {"statusCode": 200, "body": "ok"}
            set_trip_phone(trip_id, phone)
            set_profile_phone(user_id, phone)
            meta = get_trip_meta(trip_id) or {}
            fare = float(meta.get("fare", 0))
            when_txt = meta.get("desired_time_text", "unspecified")
            tg_send_message(
                chat_id,
                f"Thanks! Phone saved: {phone}\nRequested time: {when_txt}\n\n"
                f"Ready to confirm ride #{trip_id}?",
                buttons=[[{"text": f"Confirm ${fare:.2f}",
                           "callback_data": f"confirm:{trip_id}"}]]
            )
            clear_session(user_id)
            return {"statusCode": 200, "body": "ok"}

        # Addresses
        if state == "await_pickup":
            put_session(user_id, "await_dropoff", {"pickup_raw": text})
            tg_send_message(chat_id, "Got it. Now enter the drop-off address:")
            return {"statusCode": 200, "body": "ok"}

        if state == "await_dropoff":
            sdata["dropoff_raw"] = text
            dep = geocode_once(sdata["pickup_raw"])
            dest = geocode_once(sdata["dropoff_raw"])
            if not dep:
                tg_send_message(
                    chat_id, "Could not find the pickup address. Please include street, city, and state.")
                clear_session(user_id)
                show_menu(chat_id)
                return {"statusCode": 200, "body": "ok"}
            if not dest:
                tg_send_message(
                    chat_id, "Could not find the drop-off address. Please include street, city, and state.")
                clear_session(user_id)
                show_menu(chat_id)
                return {"statusCode": 200, "body": "ok"}

            distance_m, duration_s = calc_route(dep, dest)
            if not distance_m or not duration_s:
                tg_send_message(
                    chat_id, "Could not calculate the route. Please check the addresses and try again.")
                clear_session(user_id)
                show_menu(chat_id)
                return {"statusCode": 200, "body": "ok"}

            miles = distance_m / 1609.34
            minutes = duration_s / 60.0
            fare = calc_fare(miles, minutes)
            trip_id = save_trip(user_id, dep, dest, miles, minutes, fare)

            buttons = [[{"text": "📆 Pick date & time",
                         "callback_data": f"datesel:{trip_id}"}]]
            msg = (
                "✅ Ride summary:\n"
                f"• Pickup: {dep['label']}\n• Drop-off: {dest['label']}\n\n"
                f"Distance: {miles:.1f} miles\nETA: {int(minutes)} min\nPrice: ${fare:.2f}\n\n"
                "When do you need the car?"
            )
            tg_send_message(chat_id, msg, buttons=buttons)
            put_session(user_id, f"await_when:{trip_id}", {})
            return {"statusCode": 200, "body": "ok"}

        # Fallback
        show_menu(chat_id)
        return {"statusCode": 200, "body": "ok"}

    # --- Callback flow (inline buttons) ---
    if "callback_query" in update:
        cq = update["callback_query"]
        chat_id = cq["message"]["chat"]["id"]
        msg_id = cq["message"]["message_id"]
        data = cq.get("data", "")
        ensure_secrets()

        if data.startswith("datesel:"):
            trip_id = data.split(":", 1)[1]
            kb = build_date_buttons(trip_id)
            tg_send_message(chat_id, "Choose a date:", buttons=kb)
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("datepick:"):
            _, trip_id, iso_d = data.split(":")
            y, m, d = map(int, iso_d.split("-"))
            try:
                tg_edit_text(chat_id, msg_id,
                             f"✅ Date: {iso_d}", clear_keyboard=True)
            except Exception as e:
                logger.warning(f"edit date keyboard failed: {e}")
                tg_edit_reply_markup_clear(chat_id, msg_id)
            kb = build_time_buttons(trip_id, y, m, d)
            tg_send_message(chat_id, f"Choose a time for {iso_d}:", buttons=kb)
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("timepick:"):
            _, trip_id, epoch = data.split(":")
            epoch_i = int(epoch)
            set_trip_when_epoch(trip_id, epoch_i)
            try:
                tg_edit_text(
                    chat_id, msg_id, f"✅ Time: {fmt_epoch_ampm(epoch_i)}", clear_keyboard=True)
            except Exception as e:
                logger.warning(f"edit time keyboard failed: {e}")
                tg_edit_reply_markup_clear(chat_id, msg_id)
            return after_when_ask_phone_or_profile(chat_id, chat_id, trip_id)

        if data.startswith("usephone:"):
            trip_id = data.split(":", 1)[1]
            prof = get_profile(chat_id) or {}
            saved_phone = prof.get("phone")
            if not saved_phone:
                tg_send_message(
                    chat_id, "No saved phone found. Please enter your number.")
                put_session(chat_id, f"await_phone:{trip_id}", {})
                return {"statusCode": 200, "body": "ok"}
            set_trip_phone(trip_id, saved_phone)
            meta = get_trip_meta(trip_id) or {}
            fare = float(meta.get("fare", 0))
            when_txt = meta.get("desired_time_text", "unspecified")
            tg_send_message(
                chat_id,
                f"Using saved phone: {saved_phone}\nRequested time: {when_txt}\n\n"
                f"Ready to confirm ride #{trip_id}?",
                buttons=[[{"text": f"Confirm ${fare:.2f}",
                           "callback_data": f"confirm:{trip_id}"}]]
            )
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("changephone:"):
            trip_id = data.split(":", 1)[1]
            tg_send_message(chat_id, "Please enter your phone number.")
            put_session(chat_id, f"await_phone:{trip_id}", {})
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("confirm:"):
            trip_id = data.split(":", 1)[1]
            meta = get_trip_meta(trip_id)
            if not meta:
                tg_send_message(
                    chat_id, "Something went wrong. Please start again.")
                return {"statusCode": 200, "body": "ok"}
            current = meta.get("status")
            if current in ("pending", "accepted", "declined"):
                try:
                    tg_edit_text(
                        chat_id, msg_id, f"ℹ️ Request #{trip_id} is already {current}.", clear_keyboard=True)
                except Exception:
                    tg_edit_reply_markup_clear(chat_id, msg_id)
                return {"statusCode": 200, "body": "ok"}
            if not meta.get("desired_time_text"):
                tg_send_message(chat_id, "Please pick date & time first.")
                return {"statusCode": 200, "body": "ok"}
            if not meta.get("passenger_phone"):
                tg_send_message(
                    chat_id, "Please enter your phone number first.")
                return {"statusCode": 200, "body": "ok"}

            # Mark as pending and disable client's Confirm button (edit the same message)
            set_trip_status(trip_id, meta["user_id"], "pending")
            try:
                tg_edit_text(
                    chat_id,
                    msg_id,
                    f"✅ Request #{trip_id} sent to the driver.\nDriver will contact you via SMS.",
                    clear_keyboard=True
                )
            except Exception:
                tg_edit_reply_markup_clear(chat_id, msg_id)

            # Broadcast to all drivers
            phone = meta.get("passenger_phone")
            fare = float(meta.get("fare", 0))
            dep = meta.get("dep_label", "")
            dest = meta.get("dest_label", "")
            miles = float(meta.get("miles", 0.0))
            mins = int(float(meta.get("minutes", 0.0)))
            when = meta.get("desired_time_text", "")
            driver_msg = (f"🚖 New ride request #{trip_id}\n"
                          f"Client phone: {phone}\nWhen: {when}\n"
                          f"{dep} → {dest}\n{miles:.1f} mi • {mins} min • ${fare:.2f}")
            for drv in _DRIVER_CHAT_IDS:
                tg_send_message(
                    drv,
                    driver_msg,
                    buttons=[
                        [{"text": f"Accept {trip_id}",
                            "callback_data": f"accept:{trip_id}:{drv}"}],
                        [{"text": f"Decline {trip_id}",
                            "callback_data": f"decline:{trip_id}:{drv}"}]
                    ]
                )
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("accept:"):
            # accept:{trip_id}:{driver_id}
            try:
                _, trip_id, driver_id = data.split(":")
            except ValueError:
                return {"statusCode": 200, "body": "ok"}

            meta = get_trip_meta(trip_id)
            if not meta:
                tg_edit_text(
                    chat_id, msg_id, f"❌ Ride #{trip_id} not found.", clear_keyboard=True)
                return {"statusCode": 200, "body": "ok"}

            if meta.get("status") == "accepted":
                taken_by = meta.get("driver_name", "another driver")
                try:
                    tg_edit_text(
                        chat_id, msg_id, f"ℹ️ Ride #{trip_id} already accepted by {taken_by}.", clear_keyboard=True)
                except Exception:
                    tg_edit_reply_markup_clear(chat_id, msg_id)
                return {"statusCode": 200, "body": "ok"}

            prof = _DRIVER_PROFILES.get(str(driver_id), {})
            dname = prof.get("name", "Driver")
            dcar = prof.get("car",  "Car")
            set_trip_driver(trip_id, driver_id, dname, dcar)
            set_trip_status(trip_id, meta["user_id"], "accepted")

            try:
                tg_edit_text(
                    chat_id, msg_id, f"✅ Ride #{trip_id} accepted.", clear_keyboard=True)
            except Exception:
                tg_edit_reply_markup_clear(chat_id, msg_id)

            tg_send_message(
                meta["user_chat_id"],
                f"✅ Your request #{trip_id} has been confirmed.\nDriver: {dname}\nCar: {dcar}\n"
                f"Driver will contact you via SMS."
            )
            tg_send_message(chat_id, f"✅ Client notified for ride #{trip_id}.")
            return {"statusCode": 200, "body": "ok"}

        if data.startswith("decline:"):
            # decline:{trip_id}:{driver_id}
            try:
                _, trip_id, driver_id = data.split(":")
            except ValueError:
                return {"statusCode": 200, "body": "ok"}

            meta = get_trip_meta(trip_id)
            try:
                tg_edit_text(
                    chat_id, msg_id, f"❌ Ride #{trip_id} declined.", clear_keyboard=True)
            except Exception:
                tg_edit_reply_markup_clear(chat_id, msg_id)

            if meta and meta.get("status") == "pending":
                # simple behavior: mark declined if still pending
                set_trip_status(trip_id, meta["user_id"], "declined")
                tg_send_message(
                    meta["user_chat_id"], f"❌ Sorry, your request #{trip_id} was declined.")
            return {"statusCode": 200, "body": "ok"}

    return {"statusCode": 200, "body": "ok"}

# ---------- Helper ----------


def after_when_ask_phone_or_profile(chat_id, user_id, trip_id):
    """Ask for phone or reuse saved phone; returns HTTP-style dict for Lambda."""
    prof = get_profile(user_id) or {}
    saved_phone = prof.get("phone")
    if saved_phone:
        tg_send_message(
            chat_id,
            "Time saved. Use your saved phone?",
            buttons=[
                [{"text": "Use saved phone",  "callback_data": f"usephone:{trip_id}"}],
                [{"text": "Enter new number", "callback_data": f"changephone:{trip_id}"}]
            ]
        )
    else:
        tg_send_message(
            chat_id, "Time saved. Please enter your phone numberttt.")
        put_session(user_id, f"await_phone:{trip_id}", {})
    return {"statusCode": 200, "body": "ok"}
