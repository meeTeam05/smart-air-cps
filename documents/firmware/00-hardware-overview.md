# 0. Hardware overview

Firmware chạy trên ESP32-S3 (`firmware/main`, ESP-IDF). File này là điểm khởi đầu trước khi đọc chi tiết peripheral/interrupt/task ở các file sau — trả lời "board này có gì, bật/tắt bằng cách nào".

## 1. Build variants

Repo có 2 file sdkconfig fragment khác nhau:

- `firmware/sdkconfig.demo` — dùng cho build demo (broker URI mặc định `wss://minhnhat05.xyz/mqtt`).
- `firmware/sdkconfig.defaults` — baseline mặc định của ESP-IDF project.

`CONFIG_SA_DEMO_NO_PERIPHERALS`: khi bật, `sensor_task` synth dữ liệu cảm biến giả (temperature/humidity/co_ppm/no2_ppm) thay vì đọc phần cứng thật — dùng để chạy demo/dev trên board không gắn đủ cảm biến, trong khi vẫn giữ nguyên toàn bộ flow MQTT/TLS/auth thật. Theo help text Kconfig: **relay, LED, và factory-reset vẫn hoạt động thật** nếu được enable — chỉ có luồng đọc cảm biến (I2C/ADC) bị virtualize, không phải toàn bộ board.

## 2. Peripheral enable flags

Mỗi peripheral vật lý có 1 cờ `CONFIG_SA_ENABLE_*` riêng trong `firmware/main/Kconfig.projbuild`, quyết định code init có chạy hay không trong `sysload_init()`. Không phải cờ nào cũng mặc định bật:

| Peripheral            | Enable flag                      | Default | Ghi chú                                                                     |
| --------------------- | -------------------------------- | ------- | --------------------------------------------------------------------------- |
| SHT3x (temp/humidity) | `CONFIG_SA_ENABLE_SHT3X`         | `y`     | I2C, `0x44`                                                                 |
| DS3231 (external RTC) | `CONFIG_SA_ENABLE_DS3231`        | `y`     | I2C, `0x68`                                                                 |
| Factory reset button  | `CONFIG_SA_ENABLE_FACTORY_RESET` | `y`     | poll, không dùng ISR                                                        |
| Relay (3 kênh)        | `CONFIG_SA_ENABLE_RELAYS`        | `n`     | GPIO output                                                                 |
| Buzzer                | `CONFIG_SA_ENABLE_BUZZER`        | `n`     | LEDC PWM                                                                    |
| GM-702B (CO sensor)   | `CONFIG_SA_ENABLE_CO_SENSOR`     | `n`     | ADC1                                                                        |
| GM-102B (NO2 sensor)  | `CONFIG_SA_ENABLE_NO2_SENSOR`    | `n`     | ADC1                                                                        |
| ILI9225 display       | `CONFIG_SA_ENABLE_ILI9225`       | `n`     | SPI2_HOST                                                                   |
| SD card               | `CONFIG_SA_ENABLE_SD_CARD`       | `n`     | reserved, chưa implement — xem [01-peripherals.md § 2.2](01-peripherals.md) |

RGB status LED (WS2812, RMT) và WiFi station không có cờ enable riêng — luôn được init trong `sysload_init()`.

Xem chi tiết pin/bus/chip từng peripheral ở [01-peripherals.md](01-peripherals.md).

Ghi chú:

- Factory reset button nên là ngắt dùng signal để gọi ra thread và xử lý tương tự poll.
