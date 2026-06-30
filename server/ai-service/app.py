from fastapi import FastAPI
import joblib
import pandas as pd
import paho.mqtt.client as mqtt
import threading
import time
import os
import uuid
import json
import psycopg2
from network import FEATURE_COLS, decode_class
from calib_baseline import BaselineManager


MQTT_BROKER = os.getenv("MQTT_BROKER", "emqx")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USERNAME = os.getenv("MQTT_USERNAME")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
PG_HOST = os.getenv("POSTGRES_HOST", "postgres")
PG_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
PG_DB = os.getenv("POSTGRES_DB", "smartair")
PG_USER = os.getenv("POSTGRES_USER", "smartair")
PG_PASSWORD = os.getenv("POSTGRES_PASSWORD")

if not MQTT_USERNAME or not MQTT_PASSWORD:
    raise RuntimeError("Missing MQTT_USERNAME or MQTT_PASSWORD")

CONFIRM_REQUIRED = 3

warning_count_by_device = {}
baselines = {}
last_ts_by_device = {}

_baselines_lock = threading.Lock()
_state_lock = threading.Lock()
_mqtt_client: mqtt.Client | None = None

app = FastAPI()
model = joblib.load("smart_air_model_v3.pkl")


# ── DB ────────────────────────────────────────────────────────────────────────

def db_conn():
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD,
    )


def get_auto_mode(device_id) -> bool:
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT auto_mode FROM devices WHERE id = %s", (device_id,))
                row = cur.fetchone()
        return bool(row[0]) if row else False
    except Exception as e:
        print(f"[{device_id}] get_auto_mode DB error: {e}", flush=True)
        return False


def log_action(device_id, relay, state, class_id, reason, sensor):
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO ai_actions
                        (device_id, relay, state, class_id, reason,
                         temperature, humidity, co_ppm, no2_ppm)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        device_id, relay, state, class_id, reason,
                        sensor.get("temperature"), sensor.get("humidity"),
                        sensor.get("co_ppm"), sensor.get("no2_ppm"),
                    ),
                )
    except Exception as e:
        print(f"[{device_id}] log_action DB error: {e}", flush=True)


# ── Relay control via MQTT ────────────────────────────────────────────────────

def publish_relay(device_id, channel, state):
    client = _mqtt_client
    if client is None:
        print(f"[{device_id}] MQTT client not ready, cannot publish relay", flush=True)
        return
    command_id = str(uuid.uuid4())
    payload = json.dumps({"command_id": command_id, "type": "relay_set", "relay": channel, "state": state})
    client.publish(f"device/{device_id}/command", payload, qos=1)


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

    # Model v3 overweights no2_ppm — override to class 2 when cooling signal is clear
    if class_id == 0 and features["delta_temp"] >= 8 and clean_sensor["co_ppm"] < 35 and clean_sensor["no2_ppm"] < 100:
        class_id = 2

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
        "sensor": clean_sensor,
    }


def apply_control(device_id, ai_result):
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
    reason = ai_result.get("meaning", "unknown")
    sensor = ai_result.get("sensor", {})

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

    relay_map = {"fan": 1, "light": 2, "buzzer": 3}
    for name, channel in relay_map.items():
        state = desired[name]
        publish_relay(device_id, channel, state)
        log_action(device_id, channel, state, class_id, reason, sensor)

    print(f"[{device_id}] Control sent: {desired}", flush=True)


def handle_telemetry(device_id, telemetry):
    current_ts = telemetry.get("ts")
    last_ts = last_ts_by_device.get(device_id)

    if current_ts is not None and current_ts == last_ts:
        return

    if current_ts is not None:
        last_ts_by_device[device_id] = current_ts

    ai_result = run_prediction(device_id, telemetry)
    print(f"[{device_id}] Telemetry: {telemetry}", flush=True)
    print(f"[{device_id}] AI result: {ai_result}", flush=True)

    if not get_auto_mode(device_id):
        print(f"[{device_id}] auto_mode=false, skipping relay control", flush=True)
        return

    apply_control(device_id, ai_result)


# ── MQTT subscriber ───────────────────────────────────────────────────────────

def _on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        print("MQTT connected, subscribing to device/+/telemetry", flush=True)
        client.subscribe("device/+/telemetry", qos=1)
    else:
        print(f"MQTT connect failed: reason_code={reason_code}", flush=True)


def _on_message(client, userdata, msg):
    try:
        parts = msg.topic.split("/")
        if len(parts) != 3:
            return
        device_id = parts[1]
        telemetry = json.loads(msg.payload.decode("utf-8"))
        handle_telemetry(device_id, telemetry)
    except Exception as e:
        print(f"MQTT on_message error: {e}", flush=True)


def start_mqtt_subscriber():
    global _mqtt_client
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.on_connect = _on_connect
    client.on_message = _on_message

    while True:
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            _mqtt_client = client
            client.loop_forever()
        except Exception as e:
            print(f"MQTT subscriber error: {e} — retrying in 5s", flush=True)
            _mqtt_client = None
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
        if get_auto_mode(device_id):
            apply_control(device_id, ai_result)
        else:
            ai_result["control_skipped"] = "auto_mode is off for this device"

    return ai_result
