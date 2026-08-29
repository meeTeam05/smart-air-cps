# 2. Device-published topics

### 2.1 `device/{id}/status`

Firmware publish retained online status ngay sau khi subscribe xong required topics trong `MQTT_EVENT_CONNECTED`, và cấu hình LWT offline cùng topic lúc khởi tạo client (`firmware/components/general/sa_mqtt/mqtt.c:457-462,713-719`).

**Publish khi nào**: mỗi lần kết nối MQTT thành công (kể cả reconnect), ngay sau khi subscribe xong `command`/`shadow/get_response`/`ota/update` — thứ tự này để `shadow/get_response` có thể được nhận ngay khi publish.

QoS `1`, retain `1` — cho cả online payload lẫn LWT.

### Online payload:

```json
{
  "online": true,
  "firmware": "1.4.2"
}
```

| Field      | Type    | Nguồn                     |
| ---------- | ------- | ------------------------- |
| `online`   | boolean | literal `true`            |
| `firmware` | string  | `CONFIG_FIRMWARE_VERSION` |

**Contract phía bridge** (`handleStatus`, `server/api/src/services/mqtt-handlers.js:136-167`):

- `online` bắt buộc phải là boolean, payload bị bỏ qua nếu sai kiểu.
- `firmware` không bắt buộc; nếu không phải string thì bridge lưu `null` và giữ nguyên `firmware_ver` cũ (`COALESCE`).
- Bridge update `devices.online`, `devices.firmware_ver`, `devices.last_seen = NOW()`, rồi phát realtime event `device.status`.
- Khi `online = true`: bridge set Redis key `announce:{deviceId}` (TTL `REDIS_TTL_ANNOUNCE = 300s`) và flush command đang `pending` cho device này.

### Offline LWT payload:

```json
{
  "online": false
}
```

**Contract:**

- Payload này đóng băng lúc firmware gọi `esp_mqtt_client_init()` (trước khi connect) — broker tự phát khi kết nối rớt bất thường, không phải lúc thiết bị chủ động ngắt.
- Không có field `firmware` trên LWT payload.

### 2.2 `device/{id}/telemetry`

`sensor_task` publish JSON telemetry mỗi tick định kỳ, luôn publish kể cả khi sensor lỗi — field cảm biến không đọc được thì set `null` thay vì bỏ field (`firmware/components/core/sensor_task/sensor_task.c:299-334`).

Payload thực tế:

```json
{
  "device_id": "aa:bb:cc:dd:ee:ff",
  "mode": "on",
  "ts": 1712345678,
  "temperature": 28.5,
  "humidity": 65.2,
  "co_ppm": 3.1,
  "no2_ppm": 0.04
}
```

| Field         | Type          | Nguồn                                |
| ------------- | ------------- | ------------------------------------ |
| `device_id`   | string        | `ctx->device_id`                     |
| `mode`        | string        | literal `"on"` lúc telemetry publish |
| `ts`          | uint32_t      | RTC/system clock                     |
| `temperature` | float \| null | SHT3x, `null` nếu không đọc được     |
| `humidity`    | float \| null | SHT3x, `null` nếu không đọc được     |
| `co_ppm`      | float \| null | GM-102B, `null` nếu không đọc được   |
| `no2_ppm`     | float \| null | GM-702B, `null` nếu không đọc được   |

**Contract phía bridge** (`validateTelemetryPayload`, `server/api/src/services/mqtt-handlers.js:35-57`):

- Payload phải là plain object, tối đa `4096` bytes (`MAX_TELEMETRY_PAYLOAD_BYTES`) — lọt qua app-level check thì vẫn còn CHECK constraint `telemetry_payload_size_check` ở DB chặn lại.
- `device_id`, nếu có trong payload, phải khớp `{id}` trên topic — không thì payload bị bỏ qua.
- `mode` bắt buộc là `"on"` hoặc `"off"`.
- `ts` bắt buộc là Unix timestamp giây hữu hạn, dương, `<= 4294967295`.
- `temperature`/`humidity`/`co_ppm`/`no2_ppm`: nếu có mặt trong payload thì phải là number hoặc `null`.

Insert & dedupe:

- Insert vào bảng `telemetry`; dedupe theo unique index `(device_id, ts, mqtt_message_id)` — `mqtt_message_id` luôn khác null vì firmware luôn publish QoS 1. Bản ghi trùng bị `ON CONFLICT DO NOTHING`, không phát realtime event.
- `ts` cũ hơn mốc `946684800` (2000-01-01) bị clamp về mốc này.
- `ts` tương lai quá `300s` so với `NOW()` bị clamp về `NOW()`.
- Insert thành công phát realtime event `telemetry.point`.

### 2.3 `device/{id}/response`

Firmware publish ack cuối cho command đã nhận trên `device/{id}/command`.

Minimum schema:

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "status": "done"
}
```

Allowed fields bridge hiện xử lý:

| Field        | Type                  | Bắt buộc | Ghi chú                                                             |
| ------------ | --------------------- | -------- | ------------------------------------------------------------------- |
| `command_id` | string                | có       | phải khớp command row hiện có                                       |
| `status`     | `"done"` \| `"error"` | có       | chỉ hai trạng thái này được bridge chấp nhận                        |
| `device_id`  | string                | không    | nếu có và không khớp topic thì payload bị bỏ qua                    |
| `reason`     | string                | không    | bridge trim và lưu vào`commands.error_message` khi `status="error"` |

Ack semantics:

- Sync handler trả `ESP_OK` -> publish `done`.
- Handler trả lỗi khác `ESP_OK` -> publish `error`.
- Handler trả `ESP_ERR_NOT_FINISHED` -> không ack ngay; worker phải publish ack sau.
- Duplicate command đã có kết quả sẽ republish cùng status cache thay vì chạy lại handler.

Bridge effects:

- `pending` có thể được chuẩn hóa sang `sent` nếu response tới trước update dispatch.
- Command chỉ transition terminal từ `sent` sang `done` hoặc `error`.
- Duplicate/stale terminal responses bị bỏ qua.

### 2.4 `device/{id}/shadow/report`

Topic này mang patch reported-state dạng flat JSON, không có wrapper `reported`.

Các nguồn publish hiện tại:

1. `sensor_task` sau mỗi telemetry tick.
2. `relay_set()` sau khi relay thay đổi thành công.
3. `device_mode_set()` khi đổi mode.
4. `device_mode_publish_current_shadow()` ngay sau MQTT reconnect bootstrap.

Ví dụ sensor patch:

```json
{
  "mode": "on",
  "temperature": 28.5,
  "humidity": 65.2,
  "co_ppm": 3.1,
  "no2_ppm": 0.04,
  "ts": 1712345678
}
```

Ví dụ relay delta:

```json
{
  "mode": "on",
  "relay_1": true,
  "ts": 1712345678
}
```

Ví dụ mode-off patch:

```json
{
  "mode": "off",
  "relay_1": false,
  "relay_2": false,
  "relay_3": false,
  "temperature": null,
  "humidity": null,
  "co_ppm": null,
  "no2_ppm": null,
  "ts": 1712345678
}
```

Allowed keys bridge hiện validate:

- `mode` -> `on` hoặc `off`
- `relay_1`, `relay_2`, `relay_3` -> boolean
- `temperature`, `humidity`, `co_ppm`, `no2_ppm` -> number hoặc null
- `ts` -> Unix timestamp giây hữu hạn nếu có

Bridge rules:

- Payload tối đa `16384` bytes.
- `payload.ts` là ordering key cho `reported`.
- Report có `ts` cũ hơn `reported.ts` hiện tại bị bỏ qua.
- Report có `ts` tương lai quá `300s` bị normalize về current time trước khi UPSERT.
- Patch hợp lệ được merge vào `device_shadows.reported` và cache Redis `shadow:{deviceId}`.

### 2.5 `device/{id}/shadow/get`

Firmware publish topic này ngay sau khi reconnect và subscribe xong required topics.

Schema hiện tại:

```json
{
  "ts": 1712345678
}
```

Bridge chỉ yêu cầu payload là plain JSON object. Sau đó bridge load shadow hiện tại và best-effort publish `shadow/get_response`.

### 2.6 `device/{id}/ota/progress`

Firmware OTA task publish JSON progress snapshots trong lúc cập nhật OTA.

Payloads thực tế hiện tại:

```json
{ "progress": 0, "status": "starting" }
```

```json
{ "progress": 10 }
```

```json
{ "progress": 100, "status": "rebooting" }
```

Các `status` firmware đang phát ra:

| Status            | Khi nào                                              |
| ----------------- | ---------------------------------------------------- |
| `starting`        | vừa dequeue OTA request                              |
| `failed`          | `esp_https_ota_begin`, `perform`, hoặc `finish` fail |
| `sha256_mismatch` | hash không khớp trước`finish()`                      |
| `busy`            | trigger mới đến khi queue OTA depth=1 đã đầy         |
| `rebooting`       | OTA thành công, chuẩn bị reboot                      |

Ghi chú:

- Progress bucket 10% trong download loop có thể không có `status`.
- Bridge hiện không validate schema OTA progress; nó chỉ cache JSON và phát realtime event.
- Notification feed app chỉ project các status terminal `rebooting` và `failed`.
