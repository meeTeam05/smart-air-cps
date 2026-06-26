from fastapi import FastAPI
import joblib
import pandas as pd
import paho.mqtt.client as mqtt
import requests
import threading
import time
import os
import psycopg2
from network import FEATURE_COLS, decode_class
from calib_baseline import BaselineManager


SERVER_API = os.getenv("SERVER_API", "http://api:3000/api")
AI_EMAIL = os.getenv("AI_EMAIL")
AI_PASSWORD = os.getenv("AI_PASSWORD")
MQTT_BROKER = os.getenv("MQTT_BROKER", "emqx")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USERNAME = os.getenv("MQTT_USERNAME")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
PG_HOST = os.getenv("POSTGRES_HOST", "postgres")
PG_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
PG_DB = os.getenv("POSTGRES_DB", "smartair")
PG_USER = os.getenv("POSTGRES_USER", "smartair")
PG_PASSWORD = os.getenv("POSTGRES_PASSWORD")

if not AI_EMAIL or not AI_PASSWORD:
    raise RuntimeError("Missing AI_EMAIL or AI_PASSWORD")
if not MQTT_USERNAME or not MQTT_PASSWORD:
    raise RuntimeError("Missing MQTT_USERNAME or MQTT_PASSWORD")

CONFIRM_REQUIRED = 3
# Cache device list for auto_mode lookups; refresh every 30s to pick up changes.
_DEVICES_CACHE_TTL = 30

warning_count_by_device = {}
last_control_by_device = {}
baselines = {}
last_ts_by_device = {}

_baselines_lock = threading.Lock()
_state_lock = threading.Lock()
_api_token: str | None = None
_token_lock = threading.Lock()
_devices_cache: list = []
_devices_cache_ts: float = 0.0
_devices_cache_lock = threading.Lock()

app = FastAPI()
model = joblib.load("smart_air_model_v3.pkl")


# ── Auth ──────────────────────────────────────────────────────────────────────

def get_token() -> str:
    global _api_token
    with _token_lock:
        if _api_token is None:
            _api_token = _login()
        return _api_token


def clear_token():
    global _api_token
    with _token_lock:
        _api_token = None


def _login():
    res = requests.post(
        f"{SERVER_API}/auth/login",
        json={"email": AI_EMAIL, "password": AI_PASSWORD},
        timeout=5,
    )
    res.raise_for_status()
    return res.json()["accessToken"]


# ── Device list cache ─────────────────────────────────────────────────────────

def _refresh_devices_cache(token):
    global _devices_cache, _devices_cache_ts
    res = requests.get(
        f"{SERVER_API}/devices",
        headers={"Authorization": f"Bearer {token}"},
        timeout=5,
    )
    res.raise_for_status()
    with _devices_cache_lock:
        _devices_cache = res.json()
        _devices_cache_ts = time.time()


def get_auto_mode(token, device_id) -> bool:
    with _devices_cache_lock:
        age = time.time() - _devices_cache_ts
        cached = list(_devices_cache)

    if age > _DEVICES_CACHE_TTL:
        try:
            _refresh_devices_cache(token)
            with _devices_cache_lock:
                cached = list(_devices_cache)
        except Exception as e:
            print(f"[{device_id}] Device cache refresh failed: {e}", flush=True)

    for device in cached:
        if device.get("id") == device_id:
            return bool(device.get("auto_mode", False))
    return False


# ── Relay control ─────────────────────────────────────────────────────────────

def get_devices(token):
    res = requests.get(
        f"{SERVER_API}/devices",
        headers={"Authorization": f"Bearer {token}"},
        timeout=5,
    )
    res.raise_for_status()
    return res.json()


def get_latest_telemetry(token, device_id):
    res = requests.get(
        f"{SERVER_API}/devices/{device_id}/telemetry?limit=1",
        headers={"Authorization": f"Bearer {token}"},
        timeout=5,
    )
    res.raise_for_status()
    data = res.json()
    if not isinstance(data, list) or not data:
        return None
    return data[0]


def set_relay(token, device_id, channel, state):
    res = requests.post(
        f"{SERVER_API}/devices/{device_id}/relay/{channel}",
        headers={"Authorization": f"Bearer {token}"},
        json={"state": bool(state)},
        timeout=5,
    )
    res.raise_for_status()
    return res.json()


# ── Baseline persistence ──────────────────────────────────────────────────────

def get_baseline(device_id):
    with _baselines_lock:
        if device_id in baselines:
            return baselines[device_id]

    bm = BaselineManager(calibration_size=30)
    saved = load_baseline_from_db(device_id)
    if saved:
        bm.long_base = saved.copy()
        bm.short_base = saved.copy()
        bm.is_calibrated = True
        print(f"[{device_id}] Loaded baseline from DB: {saved}", flush=True)

    with _baselines_lock:
        if device_id not in baselines:
            baselines[device_id] = bm
        return baselines[device_id]


def db_conn():
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD,
    )


def load_baseline_from_db(device_id):
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT temp_base, hum_base, co_base, no2_base FROM ai_baselines WHERE device_id = %s",
                    (device_id,),
                )
                row = cur.fetchone()
        if not row:
            return None
        return {
            "temp_base": float(row[0]),
            "hum_base": float(row[1]),
            "co_base": float(row[2]),
            "no2_base": float(row[3]),
        }
    except Exception as e:
        print(f"[{device_id}] Load baseline DB error: {e}", flush=True)
        return None


def save_baseline_to_db(device_id, baseline_values):
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO ai_baselines (device_id, temp_base, hum_base, co_base, no2_base, updated_at)
                    VALUES (%s, %s, %s, %s, %s, NOW())
                    ON CONFLICT (device_id) DO UPDATE SET
                        temp_base = EXCLUDED.temp_base,
                        hum_base  = EXCLUDED.hum_base,
                        co_base   = EXCLUDED.co_base,
                        no2_base  = EXCLUDED.no2_base,
                        updated_at = NOW()
                    """,
                    (
                        device_id,
                        float(baseline_values["temp_base"]),
                        float(baseline_values["hum_base"]),
                        float(baseline_values["co_base"]),
                        float(baseline_values["no2_base"]),
                    ),
                )
    except Exception as e:
        print(f"[{device_id}] Save baseline DB error: {e}", flush=True)


# ── Prediction + control ──────────────────────────────────────────────────────

def run_prediction(device_id, sensor):
    required = ["temperature", "humidity", "co_ppm", "no2_ppm"]
    for key in required:
        if key not in sensor or sensor[key] is None:
            return {"error": f"missing field: {key}"}

    try:
        clean_sensor = {
            "temperature": float(sensor["temperature"]),
            "humidity": float(sensor["humidity"]),
            "co_ppm": float(sensor["co_ppm"]),
            "no2_ppm": float(sensor["no2_ppm"]),
        }
    except (TypeError, ValueError) as e:
        return {"error": f"invalid sensor value: {e}"}

    baseline = get_baseline(device_id)

    if not baseline.is_calibrated:
        baseline.add_calibration_sample(clean_sensor)
        if baseline.is_calibrated:
            save_baseline_to_db(device_id, baseline.long_base)
            print(f"[{device_id}] Baseline saved to DB: {baseline.long_base}", flush=True)
        return {
            "device_id": device_id,
            "status": "calibrating",
            "samples": len(baseline.buffer),
            "required": baseline.calibration_size,
        }

    features = baseline.make_feature_vector(clean_sensor)
    X = pd.DataFrame([features], columns=FEATURE_COLS)
    class_id = int(model.predict(X)[0])
    try:
        result = decode_class(class_id)
    except (KeyError, ValueError):
        return {"error": f"model predicted unknown class: {class_id}"}

    baseline.update_baseline(clean_sensor, class_id)
    save_baseline_to_db(device_id, baseline.long_base)
    return {
        "device_id": device_id,
        "class_id": class_id,
        "meaning": result["meaning"],
        "fan": result["fan"],
        "light": result["light"],
        "buzzer": result["buzzer"],
        "features": features,
    }


def apply_control(token, device_id, ai_result):
    if ai_result.get("status") == "calibrating":
        return
    if "error" in ai_result:
        return

    desired = {
        "fan": bool(ai_result["fan"]),
        "light": bool(ai_result["light"]),
        "buzzer": bool(ai_result["buzzer"]),
    }
    class_id = ai_result.get("class_id", 0)

    with _state_lock:
        if class_id != 0:
            warning_count_by_device[device_id] = warning_count_by_device.get(device_id, 0) + 1
        else:
            warning_count_by_device[device_id] = 0
        current_count = warning_count_by_device[device_id]

    if class_id != 0 and current_count < CONFIRM_REQUIRED:
        print(
            f"[{device_id}] Warning detected but waiting confirm {current_count}/{CONFIRM_REQUIRED}",
            flush=True,
        )
        return

    with _state_lock:
        if last_control_by_device.get(device_id) == desired:
            print(f"[{device_id}] Control unchanged, skip", flush=True)
            return

    r1 = set_relay(token, device_id, 1, desired["fan"])
    r2 = set_relay(token, device_id, 2, desired["light"])
    r3 = set_relay(token, device_id, 3, desired["buzzer"])

    with _state_lock:
        last_control_by_device[device_id] = desired

    print(f"[{device_id}] Control sent:", r1, r2, r3, flush=True)


def handle_telemetry(device_id, telemetry):
    """Process a single telemetry reading from MQTT. Called from MQTT thread."""
    current_ts = telemetry.get("ts")
    last_ts = last_ts_by_device.get(device_id)

    if current_ts is not None and current_ts == last_ts:
        return

    if current_ts is not None:
        last_ts_by_device[device_id] = current_ts

    ai_result = run_prediction(device_id, telemetry)
    print(f"[{device_id}] Telemetry: {telemetry}", flush=True)
    print(f"[{device_id}] AI result: {ai_result}", flush=True)

    try:
        token = get_token()
        if not get_auto_mode(token, device_id):
            print(f"[{device_id}] auto_mode=false, skipping relay control", flush=True)
            return
        apply_control(token, device_id, ai_result)
    except requests.exceptions.HTTPError as e:
        print(f"[{device_id}] HTTP error in handle_telemetry: {e}", flush=True)
        clear_token()
    except Exception as e:
        print(f"[{device_id}] Error in handle_telemetry: {e}", flush=True)


# ── MQTT subscriber ───────────────────────────────────────────────────────────

def _on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        print("MQTT connected, subscribing to device/+/telemetry", flush=True)
        client.subscribe("device/+/telemetry", qos=1)
    else:
        print(f"MQTT connect failed: reason_code={reason_code}", flush=True)


def _on_message(client, userdata, msg):
    try:
        # Topic pattern: device/<device_id>/telemetry
        parts = msg.topic.split("/")
        if len(parts) != 3:
            return
        device_id = parts[1]

        import json
        telemetry = json.loads(msg.payload.decode("utf-8"))
        handle_telemetry(device_id, telemetry)
    except Exception as e:
        print(f"MQTT on_message error: {e}", flush=True)


def start_mqtt_subscriber():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.on_connect = _on_connect
    client.on_message = _on_message

    while True:
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            client.loop_forever()
        except Exception as e:
            print(f"MQTT subscriber error: {e} — retrying in 5s", flush=True)
            time.sleep(5)


# ── FastAPI lifecycle ─────────────────────────────────────────────────────────

@app.on_event("startup")
def startup_event():
    thread = threading.Thread(target=start_mqtt_subscriber, daemon=True)
    thread.start()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict")
def predict(sensor: dict):
    device_id = sensor.get("device_id", "manual-test")
    ai_result = run_prediction(device_id, sensor)

    if "device_id" in sensor:
        try:
            token = get_token()
            if get_auto_mode(token, device_id):
                apply_control(token, device_id, ai_result)
            else:
                ai_result["control_skipped"] = "auto_mode is off for this device"
        except requests.exceptions.HTTPError:
            clear_token()
            ai_result["control_error"] = "relay control failed (auth error)"
        except Exception as e:
            ai_result["control_error"] = str(e)

    return ai_result
