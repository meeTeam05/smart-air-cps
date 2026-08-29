# 3. FreeRTOS tasks

## 1. App tasks (11)

10 task tự gọi `xTaskCreate`/`xTaskCreatePinnedToCore` trong repo, cộng 1 "main task" ẩn (ESP-IDF tự tạo để chạy `app_main`, tự xóa sau khi boot xong — xem mục 1.11 và [04-boot-sequence.md](04-boot-sequence.md)).

| #   | Task name              | Function                     | File:line                | Stack                             | Prio                    | Core                           |
| --- | ----------------------- | ----------------------------- | -------------------------- | ------------------------------------ | -------------------------- | --------------------------------- |
| 1   | `calibration_task`      | `calibration_task_fn`         | `sysload.c:326`            | 4096                                 | 3                           | `APP_CPU_NUM`                     |
| 2   | `ota_task`               | `ota_task_fn`                 | `ota.c:207`                 | 8192                                 | 3                           | `APP_CPU_NUM`                     |
| 3   | `buzzer_task`            | `buzzer_task_fn`              | `buzzer.c:100`              | 2048                                 | 2                           | không pin                          |
| 4   | `ble_prov_t`             | `prov_task`                    | `ble_prov.c:401`            | 4096                                 | 5                           | `APP_CPU_NUM`                     |
| 5   | `fr_task`                | `factory_reset_task`          | `factory_reset.c:164`       | 3072                                 | 4                           | `APP_CPU_NUM`                     |
| 6   | `mqtt_task`              | `mqtt_task`                    | `mqtt.c:844`                 | 6144                                 | 6                           | `APP_CPU_NUM`                     |
| 7   | `config_reboot`          | `restart_task`                | `httpd.c:156`                | 2048                                 | 5                           | không pin                          |
| 8   | `led_task`               | `led_task`                     | `led.c:211`                  | 2048                                 | 4                           | `APP_CPU_NUM`                     |
| 9   | `display_service`        | `display_task`                | `display_service.c:919`     | 8192                                 | 5                           | `tskNO_AFFINITY`                  |
| 10  | `sensor_task`            | `sensor_task_fn`              | `sensor_task.c:420`          | 4096                                 | 5                           | `APP_CPU_NUM`                     |
| 11  | main (boot, tự xóa)     | `app_main` -> `sysload_init` | `main.c:18`                  | `CONFIG_ESP_MAIN_TASK_STACK_SIZE`    | 1 (mặc định ESP-IDF)      | `CONFIG_ESP_MAIN_TASK_AFFINITY`   |

Task #10 dùng hằng số `#define` (`SENSOR_TASK_NAME`/`SENSOR_TASK_STACK_SIZE`/`SENSOR_TASK_PRIORITY`, khai báo tại `sensor_task.c:26-28`) thay vì literal trực tiếp trong lệnh `xTaskCreatePinnedToCore` — giá trị thật là `"sensor_task"`/`4096`/`5` như bảng trên.

**Task Watchdog Timer (TWDT)**: grep toàn repo `esp_task_wdt`/`TASK_WDT` ra 0 kết quả — **không có app task nào trong 11 task trên được đăng ký với TWDT** (`esp_task_wdt_add()` không được gọi ở đâu cả). Chỉ idle task được ESP-IDF tự watch theo mặc định. Nghĩa là nếu 1 trong 11 task này bị treo (deadlock, vòng lặp vô hạn không nhường CPU), hệ thống sẽ không tự phát hiện và reset — khác với giả định thường gặp rằng ESP-IDF luôn có watchdog bảo vệ mọi task.

### 1.1 `calibration_task`

Block trên `xQueueReceive(s_calibration_queue, ..., portMAX_DELAY)`. Producer: MQTT command handler khi nhận `calibrate_co`/`calibrate_no2` (xem [documents/mqtt/03-broker-to-device-topics.md](../mqtt/03-broker-to-device-topics.md)). Khi có request, chạy `gm702b_calibrate`/`gm102b_calibrate`, lưu R0 qua `config_save_gas_r0`, rồi publish MQTT command ack. Chỉ được start nếu init gas sensor thành công (`sysload.c:1004-1009`).

### 1.2 `ota_task`

Block trên `xQueueReceive(s_ota_queue, &msg, portMAX_DELAY)`. Producer: OTA trigger từ `device/{id}/ota/update`. Khi có trigger, chạy vòng lặp `esp_https_ota_begin/perform`, publish progress mỗi 10%, verify SHA256 trước `esp_https_ota_finish`.

### 1.3 `buzzer_task`

Block trên `xQueueReceive(s_buzzer_queue, &duration_ms, portMAX_DELAY)`. Khi nhận, bật buzzer, `vTaskDelay(duration_ms)`, tắt buzzer.

### 1.4 `ble_prov_t`

Block trên `ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(CONFIG_SA_PROV_TIMEOUT_MS))`, chờ BLE GATT callback đưa SSID/password vào. Timeout -> set `PROV_FAIL_BIT` rồi tự xóa. Thành công -> thử `wifi_sta_connect`, lưu credential vào NVS, set event group báo kết quả. Task one-shot, không phải vòng lặp dài hạn — tự xóa sau khi xong.

### 1.5 `fr_task`

Không block trên queue/notify — poll `gpio_get_level()` mỗi `POLL_MS`, theo dõi thời gian giữ nút, cập nhật LED làm feedback, gọi `factory_reset_run()` khi giữ đủ `SA_FACTORY_RESET_HOLD_MS`.

### 1.6 `mqtt_task`

Build `esp_mqtt_client_config_t` (broker URI, credential theo device_id, LWT `{"online":false}` — xem [documents/mqtt/00-runtime-boundary.md](../mqtt/00-runtime-boundary.md)), gọi `esp_mqtt_client_init`, đăng ký event handler, start client, rồi notify caller là đã start xong. Việc xử lý event/keepalive MQTT thực tế nằm trong task nội bộ của component esp-mqtt (không phải `xTaskCreate` thứ 2 trong repo này — xem mục 2).

### 1.7 `config_reboot`

One-shot: `vTaskDelay(750ms)` rồi `esp_restart()`. Spawn từ HTTP handler `POST /api/config` để trả response về app trước khi board tự reboot.

### 1.8 `led_task`

Block trên `ulTaskNotifyTake`. Khi được đánh thức (bởi `blink_timer_cb` esp_timer hoặc `led_set_state()` từ task khác — xem [02-interrupts-timers.md](02-interrupts-timers.md)), đọc state LED dưới `portENTER_CRITICAL` spinlock rồi ghi màu qua RMT.

### 1.9 `display_service`

Chạy `init_runtime()` 1 lần (bring-up LVGL/ILI9225), báo `s_init_done` semaphore, tự xóa nếu init lỗi. Nếu init OK thì loop: `lv_timer_handler()`, render lại màn hình mỗi `DISPLAY_UI_REFRESH_MS` (250ms) qua `render_screen()`, `vTaskDelay(DISPLAY_TASK_DELAY_MS)` (10ms) mỗi vòng.

### 1.10 `sensor_task`

Loop `vTaskDelay(pdMS_TO_TICKS(SA_SENSOR_POLLING_INTERVAL))` (`sensor_task.c:208`), flush pending telemetry/shadow payload nếu có, đọc SHT3x/DS3231/GM702B/GM102B (hoặc synth data giả nếu `SA_DEMO_NO_PERIPHERALS`), publish telemetry/shadow JSON qua MQTT (xem [documents/mqtt/02-device-published-topics.md](../mqtt/02-device-published-topics.md)).

**Lưu ý đơn vị**: Kconfig hiển thị `CONFIG_SA_SENSOR_POLLING_INTERVAL` là "Sensor Polling Interval **Seconds**" (mặc định 5, range 1-60), nhưng macro `SA_SENSOR_POLLING_INTERVAL` dùng trong code (`config.h:58`) đã tự nhân `* 1000` để quy đổi ra ms trước khi đưa vào `pdMS_TO_TICKS()`. Không phải bug — nhưng đọc code ở tầng `sensor_task.c` mà không biết macro này đã quy đổi thì dễ hiểu nhầm đơn vị là ms thay vì giây.

### 1.11 Main task (boot, ẩn)

`main/main.c:15-19` — `app_main()` chỉ log rồi gọi `sysload_init()` (`main.c:18`). Task này là task ESP-IDF tự tạo để gọi `app_main` (`main`), chạy đồng bộ toàn bộ chuỗi boot stage, rồi tự `vTaskDelete(NULL)` sau khi orchestrate xong (hoặc khi vào safe-mode sau quá nhiều lần retry lỗi) — không có vòng lặp dài hạn như 10 task còn lại. Chi tiết đầy đủ chuỗi boot stage xem [04-boot-sequence.md](04-boot-sequence.md).

## 2. Framework-internal tasks (5)

Các task này do component bên thứ ba (ESP-IDF/esp-mqtt/NimBLE) tự spawn bên trong lúc gọi API tương ứng — không có lệnh `xTaskCreate` trực tiếp nào cho chúng nằm trong code app của repo này, nhưng chúng vẫn chiếm RAM/CPU thật trên board nên cần biết khi tính tổng số task chạy thực tế.

| Task                          | Owner component  | Spawn point                                                      | Ghi chú                                                                            |
| ------------------------------ | ------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| httpd worker                   | `esp_http_server`  | `httpd_start()` trong `httpd.c:193`                                | Framework tự spawn, không thấy `xTaskCreate` trực tiếp trong repo                   |
| MQTT client                    | esp-mqtt component | `esp_mqtt_client_start()` (gọi từ `mqtt_task`, `mqtt.c:844`)       | `mqtt_task` chỉ lo init/start; event/keepalive thực tế do task này làm              |
| NimBLE host                    | NimBLE porting     | `nimble_port_freertos_init(nimble_host_task)`, `ble_prov.c:437`    | Hàm task body (`nimble_host_task`, `ble_prov.c:363-368`) là code của repo, nhưng lệnh spawn nằm trong NimBLE porting layer — hybrid case. Chỉ sống lúc provisioning. |
| `sys_evt` (default event loop) | `esp_event`         | `esp_event_loop_create_default()`, `sysload.c:736`                 | `wifi_event_handler` (`wifi.c:193`) thực thi trên task này                          |
| esp_timer service               | ESP-IDF esp_timer   | tự khởi tạo bởi ESP-IDF khi timer đầu tiên với `dispatch_method = ESP_TIMER_TASK` được tạo | Cả 2 timer `display_tick` và `led_blink` (xem [02-interrupts-timers.md](02-interrupts-timers.md)) chạy callback trên task này, không phải ISR thật |

Tổng task chạy thực tế trên board (khi đã provision và đủ peripheral): **11 app task + 5 framework task = 16**, chưa tính main task đã tự xóa sau boot.
