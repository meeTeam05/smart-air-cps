# 3. Broker-to-device topics

### 3.1 `device/{id}/command`

API bridge publish command JSON với envelope:

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "type": "relay_set",
  "relay": 1,
  "state": true
}
```

Generic command types mà API hiện chấp nhận:

- `relay_set`
- `device_mode`
- `set_time`
- `calibrate_co`
- `calibrate_no2`

Bridge-side validation:

- `payload` phải là plain object.
- `type` phải thuộc whitelist trên.
- `set_config` và `ota_update` bị reject ở generic REST endpoint.
- `relay_set` chỉ nhận `type`, `relay`, `state`.
- `device_mode` chỉ nhận `type`, `mode`.
- `set_time` chỉ nhận `type`, `ts`.
- `calibrate_*` chỉ nhận `type`.

Firmware-side validation và handling:

- Inbound payload cho `command` bị drop nếu tổng payload > `512` bytes.
- `set_time` được xử lý trực tiếp trong MQTT component qua `mqtt_register_time_sync_cb`.
- `relay_set`, `device_mode`, `calibrate_co`, `calibrate_no2` được dispatch qua bảng handler đăng ký bởi `sysload.c`.
- `set_config` luôn bị firmware reject trên MQTT với log hướng dẫn dùng local `POST /api/config`.
- Unsupported command type hoặc thiếu field -> command ack `error`.

#### `relay_set`

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "type": "relay_set",
  "relay": 1,
  "state": true
}
```

Behavior:

- `relay` phải là integer `1..3`.
- `state` phải là boolean.
- `relay_set()` trả `ESP_ERR_INVALID_STATE` nếu `device_mode` đang OFF.
- Thành công sẽ persist NVS, publish `shadow/report`, và beep buzzer.

#### `device_mode`

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "type": "device_mode",
  "mode": "off"
}
```

Behavior:

- `mode` phải là `on` hoặc `off`.
- Chuyển OFF sẽ publish final null telemetry rồi publish mode-off shadow.
- Chuyển ON sẽ enable sensor task và publish mode-on shadow với relay state hiện tại.

#### `set_time`

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "type": "set_time",
  "ts": 1777631761
}
```

Behavior:

- `ts` phải là Unix timestamp giây hữu hạn trong khoảng `1..4294967295`.
- Callback hiện tại update system clock; nếu DS3231 enable thì còn ghi RTC.

#### `calibrate_co` / `calibrate_no2`

```json
{
  "command_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "type": "calibrate_co"
}
```

Behavior:

- Command được enqueue vào calibration worker queue.
- Worker lấy baseline R0 trong khoảng 3 phút, bỏ outlier, reject nếu mẫu không ổn định, rồi publish ack sau khi persist hoàn tất.
- Nếu queue đầy hoặc không khởi tạo, command kết thúc bằng `error`.
- Nếu không có khí chuẩn / thiết bị tham chiếu, R0 calibration chỉ hỗ trợ đo tương đối, xu hướng, và cảnh báo; không biến `co_ppm` / `no2_ppm` thành phép đo chuẩn tuyệt đối.
- Gas calibration thuộc sensor vật lý và được lưu trong NVS partition `calib`, nên physical factory reset không xóa `r0_co` / `r0_no2`; người dùng có thể chạy lại `calibrate_*` từ app để overwrite baseline.

### 3.2 `device/{id}/shadow/get_response`

Bridge publish topic này trong ba tình huống:

- thiết bị vừa gọi `shadow/get`
- app gọi `PUT /api/devices/:id/shadow/desired` khi device đang online
- các flow nội bộ khác tái dùng `publishShadowGetResponse()`

Schema hiện tại:

```json
{
  "desired": {
    "mode": "on",
    "relay_1": true
  },
  "delta": {
    "mode": "on",
    "relay_1": true
  },
  "ts": 1712345678
}
```

Meaning:

- `desired` là desired state hiện tại.
- `delta` = `desired - reported` theo `computeDelta()`.
- `ts` là thời điểm bridge publish response này.

Constraints:

- API chỉ cho desired keys `mode`, `relay_1`, `relay_2`, `relay_3`.
- API reject mọi payload muốn bật relay khi effective desired mode là `off`.
- Inbound payload này vào firmware bị drop nếu > `512` bytes.

Firmware apply rules:

- Firmware ưu tiên apply `delta` nếu `delta` là object; nếu không có thì fallback sang `desired`.
- Chỉ `mode` và `relay_1..3` được apply; key khác bị log là unsupported và bị bỏ qua.
- Nếu patch set `mode="off"` thì relay keys trong cùng patch không được apply tiếp.
- Nếu relay key xuất hiện khi mode hiện tại OFF thì relay key đó bị bỏ qua.

### 3.3 `device/{id}/ota/update`

OTA trigger hiện có thể do API bridge publish khi app gọi `POST /api/devices/:id/ota`; manual broker/admin publish vẫn là fallback operator path.

Minimum payload firmware chấp nhận:

```json
{
  "url": "https://example.com/ota/smart-air.bin",
  "sha256": "a3f5b2c1d4e6f7890123456789abcdef0123456789abcdef0123456789abcdef"
}
```

Constraints:

- `url` và `sha256` phải là string.
- `sha256` phải cùng loại digest mà firmware verify:
  - với ESP-IDF app image có `hash_appended=1`, giá trị này là `app image digest` được append trong image, không phải `sha256sum` của cả file `.bin`
  - nếu artifact không có appended hash thì mới fallback sang SHA-256 của toàn bộ file
- `url` phải bắt đầu bằng `https://`.
- Firmware drop inbound OTA payload nếu > `512` bytes.
- `url` phải fit buffer OTA nội bộ `256` bytes cả null terminator.
- Extra keys hiện bị firmware bỏ qua.
