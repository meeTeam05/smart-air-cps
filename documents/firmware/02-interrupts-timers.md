# 2. Interrupts and timers

## 1. GPIO hardware interrupts

**Không có `gpio_isr_handler_add()` và không có `IRAM_ATTR` ở bất kỳ đâu trong `firmware/`** — đã grep toàn repo, 0 kết quả cho cả hai. Firmware hiện tại không dùng GPIO interrupt nào, kể cả cho nút factory-reset (xem [01-peripherals.md § 4.3](01-peripherals.md)) — nút này chủ động set `intr_type = GPIO_INTR_DISABLE` và poll bằng task.

Đừng giả định có ngắt GPIO ở đâu đó trong firmware này — không có.

## 2. RMT notify-from-ISR pattern (RGB LED)

Duy nhất 1 chỗ trong code có code phòng thủ cho ISR context: `request_led_refresh()` (`firmware/components/general/led/led.c:57`).

```c
if (xPortInIsrContext()) {
    vTaskNotifyGiveFromISR(s_led_task, &higher_priority_task_woken);
    portYIELD_FROM_ISR(higher_priority_task_woken);
} else {
    xTaskNotifyGive(s_led_task);
}
```

Hàm này được gọi từ 2 nơi:

- `blink_timer_cb` (`led.c:121`) — callback của `esp_timer`, nhưng timer này cấu hình `dispatch_method = ESP_TIMER_TASK` (`led.c:202`), nghĩa là chạy trong esp_timer service task, **không phải ISR context thật**.
- `led_set_state()` (`led.c:239`) — gọi từ task bình thường (VD `sysload.c`).

Kết luận: nhánh `vTaskNotifyGiveFromISR` tồn tại để an toàn nếu sau này có ai gọi `request_led_refresh()` từ 1 ISR thật, nhưng ở cách wiring hiện tại **nhánh này không được thực thi** — mọi lần gọi đều đi qua nhánh `else` (task context thông thường).

`led_task` (`led.c:83-104`) là consumer: block trên `ulTaskNotifyTake(pdTRUE, portMAX_DELAY)`, khi được đánh thức thì đọc state LED dưới `portENTER_CRITICAL(&s_spinlock)` rồi gọi `write_color()` (RMT transmit).

## 3. esp_timer software timers

Đây là timer phần mềm (callback chạy trong esp_timer service task, không phải ngắt phần cứng CPU), nhưng vẫn là nguồn "đánh thức định kỳ" đáng liệt kê cùng chủ đề interrupt/timing.

### 3.1 `display_tick`

`firmware/components/core/display_service/display_service.c:812-820`. Tạo tại `display_service.c:816`, chạy `esp_timer_start_periodic()` mỗi `DISPLAY_TICK_MS` = 5 ms (`display_service.c:37,820`). Callback `lv_tick_cb` (`display_service.c:167-170`) chỉ gọi `lv_tick_inc(5)` — nuôi tick counter nội bộ của LVGL, không notify task nào.

### 3.2 `led_blink`

`firmware/components/general/led/led.c:198-224`. `dispatch_method = ESP_TIMER_TASK` (`led.c:202`), chạy mỗi 500 ms (`led.c:218`). Callback (`led.c:106-122`) toggle `s_led_on` dưới critical section nếu color-table entry hiện tại có `blink = true`, rồi gọi `request_led_refresh()` để đánh thức `led_task` (xem mục 2 ở trên).
