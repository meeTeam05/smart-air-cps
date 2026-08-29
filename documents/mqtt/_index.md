# MQTT Protocol — smart-air

> Tài liệu này (`documents/mqtt/`) là nguồn sự thật cho giao tiếp MQTT giữa firmware ESP32 và broker/server, tách theo từng chủ đề để dễ tra cứu.
> Hợp đồng app production vẫn là REST + SSE; app không dùng MQTT trực tiếp trong flow hiện tại.

## Mục lục

- [00 · Runtime boundary](00-runtime-boundary.md) — ai nói chuyện với ai, broker URI, auth, QoS
- [01 · Topic ownership](01-topic-ownership.md) — bảng đầy đủ 9 topic, direction, QoS, retain
- [02 · Device-published topics](02-device-published-topics.md) — `status`, `telemetry`, `response`, `shadow/report`, `shadow/get`, `ota/progress`
- [03 · Broker-to-device topics](03-broker-to-device-topics.md) — `command` (relay_set, device_mode, set_time, calibrate_*), `shadow/get_response`, `ota/update`
- [04 · Delivery, ordering, and retry behavior](04-delivery-ordering-retry.md) — command queue, dedupe, shadow ordering, telemetry ordering/dedupe, bridge session persistence + QoS 1 redelivery, reconnect bootstrap
- [05 · Security and provisioning constraints](05-security-provisioning.md) — ACL, TLS, provisioning sequence
- [06 · App boundary](06-app-boundary.md) — vì sao app production không dùng MQTT trực tiếp
