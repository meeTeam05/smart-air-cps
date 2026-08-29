# 4. Boot sequence

Toàn bộ orchestration nằm trong `sysload_init()` (`firmware/components/core/sysload/sysload.c:914`), chạy đồng bộ trên main task (xem [03-tasks.md § 1.11](03-tasks.md)). `app_main()` (`main/main.c:15-19`) chỉ log rồi gọi thẳng hàm này — không có logic boot nào khác nằm ngoài `sysload.c`.

## 1. Thứ tự stage

Mỗi bước dưới đây là 1 hàm `static void ..._stage(...)` riêng trong `sysload.c`, chạy tuần tự — thứ tự có ý nghĩa (VD: I2C phải xong trước khi init sensor, WiFi/BLE phải xong trước khi có MQTT credential):

| #   | Stage                                                                      | Dòng tham chiếu       | Việc làm                                                                                                                                 |
| --- | -------------------------------------------------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | LED init                                                                   | `sysload.c:914-918`   | Khởi tạo RGB LED (RMT)                                                                                                                   |
| 2   | Factory-reset GPIO init                                                    | `sysload.c:921`       | Setup poll nút factory-reset                                                                                                             |
| 3   | Display bring-up (tùy chọn)                                                | `sysload.c:924`       | Nếu `CONFIG_SA_ENABLE_ILI9225`                                                                                                           |
| 4   | NVS init                                                                   | `sysload.c:927`       | `nvs_flash_init()` + `nvs_flash_init_partition(SA_NVS_CALIB_PARTITION)` (`sysload.c:710,719`)                                            |
| 5   | Network stack init                                                         | `sysload.c:930`       | `esp_netif`, `esp_event_loop_create_default()` (`sysload.c:736`)                                                                         |
| 6   | I2C bus init                                                               | `sysload.c:935`       | `init_i2c_bus_stage`                                                                                                                     |
| 7   | SHT3x/DS3231 device init                                                   | `sysload.c:939-959`   | Instantiate 2 device I2C                                                                                                                 |
| 8   | ADC bus + gas sensor init + start `calibration_task`                       | `sysload.c:964-1010`  | Chỉ chạy nếu CO/NO2 sensor bật                                                                                                           |
| 9   | WiFi station init                                                          | `sysload.c:1013`      | `init_wifi_stage`                                                                                                                        |
| 10  | BLE provisioning nếu `ble_prov_is_provisioned()` = false (`sysload.c:773`) | `sysload.c:1016`      | Chạy `ble_prov_t` task, chờ SSID/password qua BLE                                                                                        |
| 11  | Load WiFi credential đã lưu + connect                                      | `sysload.c:1021-1022` | `connect_wifi_stage`                                                                                                                     |
| 12  | Resolve device ID / MQTT credential từ NVS                                 | `sysload.c:1028-1029` | `load_runtime_config_stage`                                                                                                              |
| 13  | Start local HTTP config server                                             | `sysload.c:1032`      | `POST /api/config`                                                                                                                       |
| 14  | Seed system clock + best-effort SNTP                                       | `sysload.c:1035-1039` | RTC/build-time fallback, `esp_netif_sntp_*` (`sysload.c:207,213,220`)                                                                    |
| 15  | Set timezone                                                               | `sysload.c:1041`      |                                                                                                                                          |
| 16  | **Early-exit nếu chưa có `secret_key`**                                    | `sysload.c:1047`      | `vTaskDelete(NULL)` — main task dừng hẳn tại đây, chờ `POST /api/config` từ app rồi board tự reboot (xem [`config_reboot`](03-tasks.md)) |
| 17  | Buzzer/relay/device-mode init + đăng ký MQTT command handler               | `sysload.c:1051`      |                                                                                                                                          |
| 18  | Đăng ký callback MQTT time-sync/shadow-sync                                | `sysload.c:1055-1056` |                                                                                                                                          |
| 19  | Start `mqtt_task`                                                          | `sysload.c:1059`      |                                                                                                                                          |
| 20  | Start `ota_task`                                                           | `sysload.c:1062`      |                                                                                                                                          |
| 21  | Start `sensor_task`                                                        | `sysload.c:1066-1106` |                                                                                                                                          |
| 22  | OTA image validate-and-commit                                              | `sysload.c:1109`      | Xác nhận image OTA hiện tại chạy ổn định                                                                                                 |
| 23  | Mark boot ready, main task tự xóa                                          | `sysload.c:1113`      | `vTaskDelete(NULL)` — kết thúc vòng đời main task                                                                                        |

**Điểm quan trọng**: stage 16 là 1 nhánh dừng thật sự, không phải lỗi — nếu board chưa từng được provision (`POST /api/config` chưa gọi lần nào), main task dừng hẳn tại đây và **không** start MQTT/OTA/sensor task. Board ở trạng thái chờ app gửi config qua HTTP local, xong thì tự `esp_restart()` (task `config_reboot`) để chạy lại từ đầu — lúc này stage 16 sẽ pass vì đã có `secret_key`.

## 2. Failure / retry / safe-mode

Mọi lỗi boot-stage đi qua `reboot_after_boot_error()` (`sysload.c:657-679`):

- Đếm số lần lỗi liên tiếp, giới hạn `SYSLOAD_BOOT_FAILURE_RETRY_LIMIT = 3`.
- Còn trong giới hạn retry -> `esp_restart()`, thử lại từ đầu.
- Vượt giới hạn retry -> vào "safe mode": gọi `vTaskDelete(NULL)` (`sysload.c:668`) để main task dừng hẳn, board không reboot loop vô hạn nữa — cần can thiệp thủ công (factory reset hoặc reflash) để thoát trạng thái này.

Riêng lỗi BLE provisioning (stage 10, `ble_prov_start()` trả khác `ESP_OK`) đi qua đường khác — `reboot_after_provision_failure()` (`sysload.c:690-696`): log lỗi, `LED_STATE_ERROR`, đợi `SYSLOAD_PROVISION_RESTART_DELAY_MS` (5s) rồi `esp_restart()` ngay, **không đếm/giới hạn retry** như `reboot_after_boot_error()` — board sẽ cứ retry provisioning vô hạn cho tới khi thành công, không có safe-mode cho nhánh này.
