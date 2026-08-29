# Firmware — smart-air

> Tài liệu này (`documents/firmware/`) là nguồn sự thật cho kiến trúc firmware ESP32-S3: peripheral vật lý, interrupt/timer, và cấu trúc FreeRTOS task — tách theo từng chủ đề để dễ tra cứu.
> Giao thức MQTT (topic, payload, delivery/retry) nằm ở [`documents/mqtt/`](../mqtt/_index.md), không lặp lại ở đây.

## Mục lục

- [00 · Hardware overview](00-hardware-overview.md) — chip, build variant (demo/defaults), bảng enable-flag từng peripheral
- [01 · Peripherals](01-peripherals.md) — theo bus: I2C (SHT3x, DS3231), SPI (ILI9225, SD-card reserved), ADC (GM-702B, GM-102B), GPIO/LEDC/RMT (relay, buzzer, factory-reset, RGB LED), Radio (WiFi, BLE)
- [02 · Interrupts and timers](02-interrupts-timers.md) — không có GPIO ISR nào trong firmware; RMT notify pattern (LED) và 2 esp_timer software timer
- [03 · FreeRTOS tasks](03-tasks.md) — 11 app task + 5 framework-internal task, mỗi task kèm cơ chế đồng bộ (queue/notify/semaphore/poll); không task nào đăng ký Task Watchdog
- [04 · Boot sequence](04-boot-sequence.md) — chuỗi ~23 stage trong `sysload_init()`, early-exit khi chưa provision, retry/safe-mode
