#!/usr/bin/env bash
# ai-predict.sh — send fake sensor data to the AI service for testing
#
# Usage:
#   ./scripts/ai-predict.sh <device_id> <temp> <humidity> <co_ppm> <no2_ppm>
#
# Example:
#   ./scripts/ai-predict.sh dc:b4:d9:13:ed:8c 26.43 65.42 23.55 23.4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

AI_SERVICE="ai"
AI_CONTAINER="sa-ai"

usage() {
    printf 'Usage: %s <device_id> <temp> <humidity> <co_ppm> <no2_ppm>\n' "$(basename "$0")"
    printf 'Example: %s dc:b4:d9:13:ed:8c 26.43 65.42 23.55 23.4\n' "$(basename "$0")"
    exit 2
}

[[ $# -eq 5 ]] || usage

DEVICE_ID="$1"
TEMP="$2"
HUMIDITY="$3"
CO_PPM="$4"
NO2_PPM="$5"

if [[ "$(service_state "$AI_SERVICE")" != "running" ]]; then
    usage_error "AI container '$AI_CONTAINER' is not running"
fi

PAYLOAD=$(printf '{"device_id":"%s","temperature":%s,"humidity":%s,"co_ppm":%s,"no2_ppm":%s}' \
    "$DEVICE_ID" "$TEMP" "$HUMIDITY" "$CO_PPM" "$NO2_PPM")

printf 'Sending: %s\n\n' "$PAYLOAD"

docker exec "$AI_CONTAINER" python3 -c "
import requests, json, sys
r = requests.post('http://localhost:8000/predict',
    json=json.loads(sys.argv[1]),
    timeout=10)
print(json.dumps(r.json(), indent=2))
" "$PAYLOAD"
