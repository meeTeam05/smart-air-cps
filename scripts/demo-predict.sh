#!/usr/bin/env bash
# demo-predict.sh — run a named AI demo scenario (3 sends = CONFIRM_REQUIRED)
#
# Usage:
#   ./scripts/demo-predict.sh <scenario>
#   ./scripts/demo-predict.sh reset        reset relay + warning counter về class 0
#
# Scenarios (files in data/demo/):
#   gas-warning   Class 1 — light + buzzer
#   cooling       Class 2 — fan + light
#   danger        Class 3 — fan + light + buzzer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

AI_SERVICE="ai"
AI_CONTAINER="sa-ai"
CONFIRM_REQUIRED=3

RESET_DEVICE_ID="dc:b4:d9:13:ed:8c"

usage() {
    printf 'Usage: %s <scenario>\n' "$(basename "$0")"
    printf 'Scenarios: gas-warning | cooling | danger | reset | calibrate\n'
    printf 'Example:   %s gas-warning\n' "$(basename "$0")"
    exit 2
}

[[ $# -eq 1 ]] || usage

# calibrate — send 30 normal samples so baseline gets saved to DB
if [[ "$1" == "calibrate" ]]; then
    if [[ "$(service_state "$AI_SERVICE")" != "running" ]]; then
        usage_error "AI container '$AI_CONTAINER' is not running"
    fi
    CALIB_PAYLOAD=$(printf '{"device_id":"%s","temperature":32.8,"humidity":59.0,"co_ppm":1.5,"no2_ppm":0.02}' "$RESET_DEVICE_ID")
    print_section "Calibrate — nạp 30 mẫu bình thường"
    info "device : $RESET_DEVICE_ID"
    info "values : temp=32.8  hum=59.0  co=1.5  no2=0.02"
    printf '\n'
    for i in $(seq 1 30); do
        RESULT=$(docker exec "$AI_CONTAINER" python3 -c "
import requests, json, sys
r = requests.post('http://localhost:8000/predict', json=json.loads(sys.argv[1]), timeout=10)
d = r.json()
if d.get('status') == 'calibrating':
    print('calibrating %d/%d' % (d.get('samples',0), d.get('required',30)))
else:
    print('done  class=%s  meaning=%s' % (d.get('class_id','?'), d.get('meaning','?')))
" "$CALIB_PAYLOAD")
        printf '  [%2d/30] %s\n' "$i" "$RESULT"
    done
    printf '\n'
    info "baseline saved to DB — future container restarts will skip calibration"
    exit 0
fi

# Handle reset command separately — no scenario file needed
if [[ "$1" == "reset" ]]; then
    if [[ "$(service_state "$AI_SERVICE")" != "running" ]]; then
        usage_error "AI container '$AI_CONTAINER' is not running"
    fi
    print_section "Reset — class 0 (tắt relay + clear counter)"
    info "device : $RESET_DEVICE_ID"
    RESET_PAYLOAD=$(printf '{"device_id":"%s","temperature":28.0,"humidity":59.0,"co_ppm":2.0,"no2_ppm":0.02}' "$RESET_DEVICE_ID")
    docker exec "$AI_CONTAINER" python3 -c "
import requests, json, sys
r = requests.post('http://localhost:8000/predict', json=json.loads(sys.argv[1]), timeout=10)
d = r.json()
print('  class=%s  meaning=%s' % (d.get('class_id', '?'), d.get('meaning', d.get('status', '?'))))
" "$RESET_PAYLOAD"
    exit 0
fi

SCENARIO_FILE="$ROOT_DIR/data/demo/$1.env"
ensure_file "$SCENARIO_FILE"

# shellcheck source=/dev/null
source "$SCENARIO_FILE"

if [[ "$(service_state "$AI_SERVICE")" != "running" ]]; then
    usage_error "AI container '$AI_CONTAINER' is not running"
fi

print_section "$LABEL"
info "scenario : $SCENARIO_FILE"
info "device   : $DEVICE_ID"
info "input    : temp=$TEMPERATURE  hum=$HUMIDITY  co=$CO_PPM  no2=$NO2_PPM"

# Run scenario CONFIRM_REQUIRED times
PAYLOAD=$(printf '{"device_id":"%s","temperature":%s,"humidity":%s,"co_ppm":%s,"no2_ppm":%s}' \
    "$DEVICE_ID" "$TEMPERATURE" "$HUMIDITY" "$CO_PPM" "$NO2_PPM")

printf '\n'
info "running scenario $CONFIRM_REQUIRED times (CONFIRM_REQUIRED=$CONFIRM_REQUIRED)"

LAST_RESULT=""
for i in $(seq 1 $CONFIRM_REQUIRED); do
    LAST_RESULT=$(docker exec "$AI_CONTAINER" python3 -c "
import requests, json, sys
r = requests.post('http://localhost:8000/predict', json=json.loads(sys.argv[1]), timeout=10)
print(json.dumps(r.json()))
" "$PAYLOAD")
    CLASS_ID=$(printf '%s' "$LAST_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('class_id','?'))")
    MEANING=$(printf '%s' "$LAST_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('meaning', d.get('status','?')))")
    printf '  [%d/%d] class=%s  meaning=%s\n' "$i" "$CONFIRM_REQUIRED" "$CLASS_ID" "$MEANING"
done

# Step 3: Summary
printf '\n'
print_section "Result"
printf '%s' "$LAST_RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d:
    print('FAIL error: ' + d['error'])
    sys.exit(1)
if d.get('status') == 'calibrating':
    print('SKIP still calibrating (%d/%d samples)' % (d.get('samples', 0), d.get('required', 30)))
    sys.exit(0)
relay_map = [(1, 'fan', d.get('fan', 0)), (2, 'light', d.get('light', 0)), (3, 'buzzer', d.get('buzzer', 0))]
on_relays  = ['relay_%d(%s)' % (r, n) for r, n, v in relay_map if v]
off_relays = ['relay_%d(%s)' % (r, n) for r, n, v in relay_map if not v]
print('PASS class=%s  meaning=%s' % (d.get('class_id', '?'), d.get('meaning', '?')))
print('     relay ON : %s' % (', '.join(on_relays)  if on_relays  else 'none'))
print('     relay OFF: %s' % (', '.join(off_relays) if off_relays else 'none'))
"
