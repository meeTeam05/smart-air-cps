# 0. Runtime boundary

MQTT hiện được dùng ở ba phía:

- Firmware ESP32-S3 kết nối broker qua `wss://minhnhat05.xyz/mqtt` theo mặc định.
- Fastify API chạy MQTT bridge nội bộ tới `mqtt://emqx:1883`.
- EMQX giữ per-device auth + ACL để cô lập topic theo `device_id`.

Các giá trị runtime hiện tại:

| Thông số                          | Giá trị repo-truth hiện tại                                              |
| --------------------------------- | ------------------------------------------------------------------------ |
| Public device broker URI mặc định | `wss://minhnhat05.xyz/mqtt`                                              |
| Public ingress path               | Cloudflare Tunnel -> `nginx` -> EMQX WebSocket `8083`                    |
| API bridge broker URI mặc định    | `mqtt://emqx:1883`                                                       |
| Device auth                       | `username = device_id`, `password = secret_key`                          |
| Bridge auth                       | `username = sa-server`, `password = EMQX_MQTT_PASSWORD`                  |
| QoS mặc định                      | `1` cho mọi publish/subscribe do code hiện tại tạo                       |
| Keep-alive device                 | `15` giây (`esp_mqtt_client_config_t.session.keepalive`)                 |
| Reconnect timeout device          | `5000` ms (`network.reconnect_timeout_ms`)                               |
| Bridge reconnect period           | `2000` ms (`config.mqtt.reconnectPeriodMs`)                              |
| Bridge connect timeout            | `30000` ms (`config.mqtt.connectTimeoutMs`)                              |
| Bridge publish timeout            | `5000` ms (`MQTT_PUBLISH_TIMEOUT_MS`, mặc định)                          |
| Bridge provision retry            | `5000` ms (`MQTT_PROVISION_RETRY_MS`, mặc định)                          |
| Bridge session type               | persistent (`clean: false`, `clientId` cố định `sa-api-bridge` mặc định) |
| Device session type               | clean session (mặc định ESP-IDF, không set `disable_clean_session`)      |
| Bridge ack mode                   | `manualAcks: true` — handler lỗi thì message không được ack              |

Ghi chú:

- `device_id` là MAC lowercase dạng `aa:bb:cc:dd:ee:ff`.
- `secret_key` chỉ xuất hiện sau `POST /api/devices`, rồi được app chuyển vào firmware qua local `POST /api/config`.
- Plain `1883` chỉ là hop nội bộ Docker cho API bridge, không phải device contract công khai.
- Bridge là 1 plugin trong Fastify API (`server/api/src/plugins/mqtt.js`), tự provision EMQX user + ACL của chính mình lúc start (`ensureBridgeUser()`) thay vì cần tạo thủ công trước — nếu provision lỗi thì retry mỗi `MQTT_PROVISION_RETRY_MS` cho tới khi thành công.
- Bridge chỉ coi là "ready" (`fastify.mqttIsReady()`) sau khi connect **và** subscribe thành công cả 6 topic wildcard `device/+/status`, `.../telemetry`, `.../response`, `.../shadow/report`, `.../shadow/get`, `.../ota/progress` — `mqttPublish()` reject nếu chưa ready. Trạng thái này lộ ra qua check `mqtt` ở `GET /health/ready`.
- Ngoài bridge, còn 1 MQTT client thứ ba dùng chung broker: AI service (`username = sa-ai` mặc định, provision bởi `ensureAiUser()`, bỏ qua nếu chưa cấu hình password) — chỉ được quyền subscribe `device/+/telemetry` và publish `device/+/command`, ACL tách biệt hoàn toàn với bridge user.
