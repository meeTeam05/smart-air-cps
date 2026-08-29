# 6. App boundary

Các điểm sau dễ gây nhầm:

- Public MQTT WebSocket endpoint tồn tại, nhưng app production hiện không subscribe MQTT trực tiếp.
- Flutter app dùng REST cho snapshot/history/command và dùng `/api/realtime` SSE cho live updates.
- Nếu có client MQTT ngoài firmware, nó phải tự dùng credential MQTT do EMQX hiểu; JWT REST không được dùng cho MQTT broker hiện tại.
