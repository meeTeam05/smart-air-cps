# 5. Security and provisioning constraints

- Device chỉ được pub/sub topic `device/{own_id}/*` theo EMQX built-in authz rules.
- `secret_key` là credential MQTT per-device, do backend sinh ra lúc đăng ký.
- Firmware mặc định verify TLS qua ESP CRT bundle khi kết nối broker public.
- Build repo hiện tại vẫn để `CONFIG_NVS_ENCRYPTION=n` và `CONFIG_FLASH_ENCRYPTION_ENABLED=n`, nên MQTT `secret_key` và Wi-Fi credentials đang nằm plaintext trong flash/NVS nếu deployment không bật lớp bảo vệ ngoài repo.

Provisioning sequence hiện tại:

1. App gọi `POST /api/devices`.
2. API tạo EMQX user + ACL cho `device_id`, trả `secret_key` đúng 1 lần.
3. App gọi local `POST http://<device-ip>/api/config` với:

```json
{
  "device_id": "aa:bb:cc:dd:ee:ff",
  "secret_key": "device secret",
  "broker_uri": "wss://minhnhat05.xyz/mqtt"
}
```

4. Firmware chỉ chấp nhận request đầu tiên khi chưa có `secret_key`, validate `device_id` phải khớp MAC thật, rồi lưu config và reboot.
5. Sau reboot, firmware mới bắt đầu login MQTT.

Security note:

- Hop local `POST /api/config` hiện là plain HTTP trên LAN, không có TLS hay bootstrap token.
- BLE provisioning và local HTTP bootstrap hiện dựa vào giả định môi trường cài đặt tin cậy.
