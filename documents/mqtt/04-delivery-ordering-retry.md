# 4. Delivery, ordering, and retry behavior

### 4.1 Command queue on the server

- REST command requests luôn insert DB row `status='pending'`.
- Nếu MQTT bridge ready, `flushPending()` cố publish command FIFO theo device.
- Publish fail sau dispatch commit sẽ cố revert row từ `sent` về `pending`.
- Pending row quá hạn `COMMAND_PENDING_TIMEOUT_SECONDS` sẽ thành `timeout`.

### 4.2 Duplicate command handling on firmware

Firmware giữ cache RAM tối đa 20 `command_id`.

- Duplicate khi command gốc còn `pending` -> bỏ qua execution, chờ ack gốc.
- Duplicate khi command đã `done` hoặc `error` -> publish lại cùng terminal ack.
- Cache không durable qua reboot.

### 4.3 Shadow ordering

- `shadow/report` dùng `payload.ts` làm ordering key.
- Older patch không được phép overwrite reported state mới hơn.
- Desired state không có timestamp riêng; bridge tính `delta` tại thời điểm publish `shadow/get_response`.

### 4.4 Telemetry ordering and dedupe

- Duplicate delivery (QoS 1 redelivery) dedupe theo unique index `(device_id, ts, mqtt_message_id)` trên bảng `telemetry` — bản ghi trùng bị `ON CONFLICT DO NOTHING`, không phát lại realtime event.
- `ts` cũ hơn mốc `946684800` (2000-01-01) bị clamp về mốc này trước khi insert.
- `ts` tương lai quá `300s` so với `NOW()` bị clamp về `NOW()`.
- Khác với `shadow/report`, telemetry không reject report có `ts` cũ hơn record trước đó — mỗi điểm hợp lệ đều được insert (trừ khi trùng dedupe key ở trên), không so sánh thứ tự với `ts` gần nhất.

### 4.5 Bridge session persistence and QoS 1 redelivery

Bridge connect với `clean: false` (`server/api/src/plugins/mqtt.js:35-44`) — session bền theo `clientId` cố định (`sa-api-bridge` mặc định). Firmware ngược lại dùng clean session mặc định của ESP-IDF (không set `disable_clean_session`).

- Khi bridge mất kết nối ngắn hạn (crash, restart, network blip), EMQX **giữ lại subscription và queue message QoS 1** cho `clientId` của bridge — message device publish trong lúc bridge down không mất, được deliver lại ngay khi bridge reconnect và subscribe lại.
- Đây là lý do command từ server gửi cho device *không* được broker queue kiểu tương tự (vì firmware dùng clean session, mất subscription/queue mỗi lần disconnect) — nên command retry phải tự cài ở tầng DB (`pending` row + `flushPending()` khi bridge/device online lại, xem § 5.1), không dựa vào cơ chế broker.
- Bridge dùng `manualAcks: true`; trong `client.handleMessage` (`mqtt.js:174-183`), nếu handler xử lý throw lỗi thì **không gọi `callback()`** — message ở lại trạng thái unacked, broker tự động redeliver khi bridge reconnect. Đây là retry ở tầng MQTT protocol cho lỗi xử lý phía bridge, tách biệt với mọi retry logic khác đã mô tả ở trên (command timeout, telemetry dedupe, shadow ordering).
- Queue depth tối đa và message expiry cho session bền này là cấu hình phía EMQX broker (`mqtt.max_mqueue_len`, session/message expiry) — không nằm trong repo này nên chưa verify được giá trị thật. Nếu bridge down quá lâu hoặc queue vượt giới hạn, message cũ vẫn có thể bị broker drop; không nên coi cơ chế này là đảm bảo không giới hạn.

### 4.6 MQTT reconnect bootstrap

Ngay sau `MQTT_EVENT_CONNECTED`, firmware hiện làm theo thứ tự:

1. subscribe `command`, `shadow/get_response`, `ota/update`
2. publish retained `status` online
3. publish current `shadow/report`
4. publish `shadow/get`

Thứ tự này quan trọng vì firmware cần subscribe xong trước khi status/shadow/get có thể kéo desired state mới về.
