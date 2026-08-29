# 1. Peripherals

Liệt kê theo bus điện — khớp cấu trúc thư mục thật (`firmware/components/drivers/*`). Mỗi mục có pin/bus config, chip thật, và cờ enable (chi tiết bảng enable ở [00-hardware-overview.md](00-hardware-overview.md)).

## 1. I2C bus

Bus dùng chung, `I2C_NUM_0`, API `driver/i2c_master` mới. Init tại `firmware/components/drivers/i2c_bus/i2cdev.c:29` (`i2c_bus_init()`, gọi `i2c_new_master_bus()` tại `i2cdev.c:69`), được gọi từ `sysload.c:756` (`init_i2c_bus_stage`).

- SDA = `CONFIG_SA_I2C_SDA_PIN` (mặc định GPIO12), SCL = `CONFIG_SA_I2C_SCL_PIN` (mặc định GPIO13).
- Clock cố định 400 kHz (`firmware/main/Kconfig.projbuild:193-222`).
- Mỗi device I2C có 1 mutex riêng bảo vệ truy cập đồng thời (`i2c_dev_create_mutex()`/`i2c_dev_take_mutex()`, `i2cdev.c:138-175`) — timeout mặc định `SA_I2C_TIMEOUT_MS` = 1000ms (Kconfig, range 100-5000). Cần thiết vì `sensor_task` đọc cả SHT3x lẫn DS3231 trên cùng bus.

### 1.1 SHT3x (temperature/humidity)

`firmware/components/drivers/i2c_devices/sht3x/sht3x.c`. Địa chỉ I2C `0x44` (`SHT3X_I2C_ADDR_GND`) hoặc `0x45` (`SHT3X_I2C_ADDR_VDD`), khai báo tại `include/sht3x.h:17-18`, validate tại `sht3x.c:178-179`. Instantiate với `0x44` tại `sysload.c:940`. Enable flag `CONFIG_SA_ENABLE_SHT3X` (mặc định `y`).

### 1.2 DS3231 (external RTC)

`firmware/components/drivers/i2c_devices/ds3231/ds3231.c`. Địa chỉ I2C cố định `0x68` (`include/ds3231.h:16`). Instantiate tại `sysload.c:953`. Enable flag `CONFIG_SA_ENABLE_DS3231` (mặc định `y`).

Driver có sẵn API cho alarm interrupt (`ds3231.c:404,417`, các bit `DS3231_CTRL_ALARM_INTS`...) nhưng **không có GPIO nào trong firmware nối tới chân INT/SQW của DS3231** — API này tồn tại nhưng không có consumer, coi như dead code ở thời điểm hiện tại.

## 2. SPI bus

### 2.1 ILI9225 (display, 176x220 TFT)

`firmware/components/drivers/spi_devices/ili9225/ili9225.c`. Host `SPI2_HOST`, config tại `display_service.c:773-780`:

| Chân     | GPIO (mặc định)        |
| -------- | ---------------------- |
| CLK      | `SA_DISP_CLK_PIN` = 1  |
| MOSI/SDA | `SA_DISP_SDA_PIN` = 2  |
| DC/RS    | `SA_DISP_RS_PIN` = 42  |
| RST      | `SA_DISP_RST_PIN` = 41 |
| CS       | `SA_DISP_CS_PIN` = 40  |

Clock mặc định `SA_DISP_SPI_HZ` = 10 MHz. Bus init `spi_bus_initialize()` tại `ili9225.c:176`, attach device `spi_bus_add_device()` tại `ili9225.c:188`. `spics_io_num = -1` — CS được bit-bang thủ công qua `gpio_config()` (`ili9225.c:154-165`), không giao cho SPI driver quản lý. Enable flag `CONFIG_SA_ENABLE_ILI9225` (mặc định `n`).

### 2.2 SD card — reserved, chưa implement

`firmware/components/drivers/spi_devices/sd_card/sd_card.c` và `include/sd_card.h` là **file rỗng** — không có driver nào thực thi. Kconfig đã reserve pin (`SA_SD_MISO_PIN`=4, `SA_SD_SCK_PIN`=5, `SA_SD_MOSI_PIN`=6, `SA_SD_CS_PIN`=7, dự kiến `SPI3_HOST`, `Kconfig.projbuild:289-320`) và cờ `CONFIG_SA_ENABLE_SD_CARD` (mặc định `n`) tồn tại, nhưng chưa có code nào dùng. Đừng nhầm đây là tính năng đang hoạt động.

Component `firmware/components/drivers/spi_bus/spi_bus.c` + `include/spi_bus.h` (lớp abstraction SPI bus dùng chung) **cũng là file rỗng** — ILI9225 driver gọi thẳng ESP-IDF SPI driver, không qua abstraction này.

## 3. ADC1

Oneshot driver + calibration curve-fitting. Init tại `firmware/components/drivers/adc_bus/adc_bus.c:55` (`adc_bus_init()` — `adc_oneshot_new_unit(ADC_UNIT_1, ...)` tại `adc_bus.c:74`, calibration `adc_cali_create_scheme_curve_fitting` 12-bit `ADC_ATTEN_DB_12` tại `adc_bus.c:82-87`). Chỉ được gọi từ `sysload.c:964` khi có ít nhất 1 gas sensor bật.

### 3.1 GM-702B (CO sensor)

`firmware/components/drivers/adc_devices/gm702b/gm702b.c:198` (`gm702b_init`). Channel = `SA_CO_ADC_CHANNEL` = `CONFIG_SA_CO_ANALOG_PIN - 1` (`config.h:82`) — pin mặc định GPIO9 → `ADC_CHANNEL_8`. Đọc qua `adc_bus_read_voltage()`. Enable flag `CONFIG_SA_ENABLE_CO_SENSOR` (mặc định `n`).

### 3.2 GM-102B (NO2 sensor)

`firmware/components/drivers/adc_devices/gm102b/gm102b.c:222` (`gm102b_init`). Channel = `SA_NO2_ADC_CHANNEL` = `CONFIG_SA_NO2_ANALOG_PIN - 1` (`config.h:83`) — pin mặc định GPIO10 → `ADC_CHANNEL_9`. Enable flag `CONFIG_SA_ENABLE_NO2_SENSOR` (mặc định `n`).

Cả 2 sensor có calibration R0 (xem `calibrate_co`/`calibrate_no2` command trong [documents/mqtt/03-broker-to-device-topics.md](../mqtt/03-broker-to-device-topics.md)), lưu NVS partition `calib`.

## 4. GPIO / LEDC / RMT

### 4.1 Relay (3 kênh)

`firmware/components/general/relay/relay.c`. Digital output thuần túy qua `gpio_config()`/`gpio_set_level()`, không dùng interrupt.

| Kênh | Pin (mặc định)                   |
| ---- | -------------------------------- |
| 1    | `CONFIG_SA_RELAY_1_PIN` = GPIO17 |
| 2    | `CONFIG_SA_RELAY_2_PIN` = GPIO18 |
| 3    | `CONFIG_SA_RELAY_3_PIN` = GPIO8  |

Active-high (`Kconfig.projbuild:346-366`). Enable flag `CONFIG_SA_ENABLE_RELAYS` (mặc định `n`).

### 4.2 Buzzer

`firmware/components/general/buzzer/buzzer.c`. Điều khiển qua LEDC PWM (không phải GPIO thuần): `LEDC_LOW_SPEED_MODE`, `LEDC_TIMER_1`, `LEDC_CHANNEL_0`, 2 kHz, duty 10-bit (`buzzer.c:25-30`), trên chân `CONFIG_SA_BUZZER_PIN` (mặc định GPIO11). Enable flag `CONFIG_SA_ENABLE_BUZZER` (mặc định `n`).

### 4.3 Factory reset button

`firmware/components/general/factory_reset/factory_reset.c:145` (`factory_reset_init`). Pin `CONFIG_SA_FACTORY_RESET_PIN` (mặc định GPIO0). `gpio_config()` set `GPIO_MODE_INPUT`, `GPIO_PULLUP_ENABLE`, **`intr_type = GPIO_INTR_DISABLE`** — chủ động không dùng interrupt, poll `gpio_get_level()` mỗi `POLL_MS` = 50ms (hardcode, `factory_reset.c:38`, không qua Kconfig) trong `factory_reset_task`. Giữ đủ `CONFIG_SA_FACTORY_RESET_HOLD_MS` (mặc định 5000ms, range 3000-10000) thì trigger full NVS erase + reboot. Enable flag `CONFIG_SA_ENABLE_FACTORY_RESET` (mặc định `y`).

### 4.4 RGB status LED (WS2812, RMT)

`firmware/components/general/led/led.c`. Pin `CONFIG_SA_LED_PIN` (mặc định GPIO48 — LED onboard ESP32-S3-DevKitC-1). Dùng RMT TX peripheral, không phải GPIO bit-bang:

- Channel `rmt_new_tx_channel()` tại `led.c:166`: `clk_src = RMT_CLK_SRC_DEFAULT`, `resolution_hz = 10 MHz`, `mem_block_symbols = 64`, `trans_queue_depth = 4`.
- Bytes encoder `rmt_new_bytes_encoder()` tại `led.c:180`, timing NRZ chuẩn WS2812B.
- Transmit qua `rmt_transmit()` trong `write_color()` (`led.c:77-80`).

Không có enable flag riêng — luôn init trong `sysload_init()`. Chi tiết cơ chế đồng bộ (RMT notify-from-ISR) xem [02-interrupts-timers.md](02-interrupts-timers.md).

Bảng màu theo state (`s_color_table`, `led.c:37-45`) — dùng khắp `sysload.c` để báo trạng thái boot/lỗi:

| State                     | Màu (R,G,B)          | Blink? | Ý nghĩa                                     |
| ------------------------- | -------------------- | ------ | ------------------------------------------- |
| `LED_STATE_BOOT`          | trắng (80,80,80)     | có     | đang boot                                   |
| `LED_STATE_BLE`           | xanh dương (0,0,180) | có     | đang BLE provisioning                       |
| `LED_STATE_WIFI`          | vàng (200,180,0)     | có     | đang connect WiFi                           |
| `LED_STATE_ONLINE`        | xanh lá (0,180,0)    | không  | online, hoạt động bình thường               |
| `LED_STATE_OTA`           | tím (120,0,120)      | có     | đang OTA update                             |
| `LED_STATE_ERROR`         | đỏ (180,0,0)         | không  | lỗi fatal (đứng yên, không nhấp nháy)       |
| `LED_STATE_FACTORY_RESET` | đỏ (180,0,0)         | có     | đang giữ nút factory-reset, còn cancel được |
| `LED_STATE_OFF`           | tắt (0,0,0)          | không  | tắt hẳn                                     |

Lưu ý: `LED_STATE_ERROR` (fatal, đứng yên) và `LED_STATE_FACTORY_RESET` (nhấp nháy, còn hủy được) dùng chung màu đỏ nhưng khác kiểu blink — đây là cách duy nhất phân biệt 2 trạng thái này bằng mắt thường.

## 5. Radio

### 5.1 WiFi (station mode)

`firmware/components/general/wifi/wifi.c`. `esp_wifi_init()` tại `wifi.c:244`; event handler cho `WIFI_EVENT`/`IP_EVENT` đăng ký tại `wifi.c:251,257`, xử lý `WIFI_EVENT_STA_DISCONNECTED` và `IP_EVENT_STA_GOT_IP`. Khởi động từ `sysload.c:765` (`init_wifi_stage`), connect tại `sysload.c:808` (`connect_wifi_stage`).

### 5.2 BLE (NimBLE, chỉ dùng cho provisioning)

`firmware/components/general/ble_prov/ble_prov.c`. `nimble_port_init()` tại `ble_prov.c:409`. Chỉ chạy trong lúc provisioning ban đầu (`ble_prov_start()`), sau đó bị teardown — không phải radio chạy song song suốt runtime như WiFi. Chi tiết task NimBLE host xem [03-tasks.md](03-tasks.md).

## 6. Không dùng

- **UART**: không có `uart_driver_install`/`uart_param_config`/`UART_NUM_*` nào trong `firmware/` — grep toàn repo ra 0 kết quả. Chỉ có UART0 console/log mặc định của ESP-IDF (không phải app quản lý), không dùng UART cho giao tiếp dữ liệu.
