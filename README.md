# smart-air

![ESP32-S3](https://img.shields.io/badge/MCU-ESP32--S3-E7352C)
![ESP-IDF 5.4.2](https://img.shields.io/badge/ESP--IDF-5.4.2-111827)
![Flutter >=3.10](https://img.shields.io/badge/Flutter-%3E%3D3.10-02569B)
![Node.js 20](https://img.shields.io/badge/Node.js-20-339933)
![License MIT](https://img.shields.io/badge/License-MIT-22C55E)

![Smart-Air](assets/hero.png)

## Introduction

`smart-air` is an ESP32-S3 indoor air quality monitor and smart home controller. It combines ESP-IDF firmware, a Fastify + EMQX + TimescaleDB server stack, and a Flutter mobile app to solve device onboarding, telemetry ingestion, remote control, and live state sync in one system.

Devices ship with BLE-based Wi-Fi provisioning and finish setup through a local HTTPS config server, then publish telemetry and shadow updates over MQTT (TLS/WSS). The app uses REST as the canonical API for auth, snapshots, history, commands, shadow, multi-home, and OTA, and receives live updates over Server-Sent Events at `GET /api/realtime`. Public traffic is terminated at Cloudflare Tunnel and proxied by Nginx to the broker, API, and OTA artifacts.

## Features

- **Firmware** (ESP-IDF v5.4.2): BLE provisioning, Wi-Fi, MQTT over TLS/WSS, HTTPS OTA with rollback/validation, SHT3x (temperature/humidity), GM702B (CO) and GM102B (NO₂) gas sensors, DS3231 RTC with SNTP sync, LVGL on ILI9225 display, 3 relay channels (Fan/Lamp/Filter) with NVS persistence, WS2812 status LED, buzzer, and factory-reset button.
- **Server**: Fastify API with PostgreSQL/TimescaleDB, Redis, and EMQX in Docker Compose; Nginx + Cloudflare Tunnel for public ingress; per-device MQTT credentials provisioned through the API; OTA artifact hosting.
- **Realtime**: Live device status, shadow, telemetry, OTA progress, and command updates over Server-Sent Events; REST remains canonical for snapshots, history, replay, and command authorization.
- **App** (Flutter + Riverpod): JWT auth with refresh-token rotation in secure storage, 5-step BLE provisioning, multi-home/room management with member invites, device dashboard with relay and device-mode controls, real-time sparkline charts, command history, sensor calibration wizard, OTA screen, in-app notifications, and adaptive light/dark theme.
- **Unity dashboard**: REST-authenticated desktop visualization for device shadow data, sensor readings, relay state, and real-time charts.

## Hardware

### Schematic

![Schematic](assets/hardware/schematic.jpg)

### PCB Layout

<p align="center">
  <img src="assets/hardware/pcb-f.jpg" alt="PCB Front" width="48%">
  <img src="assets/hardware/pcb-b.jpg" alt="PCB Back" width="48%">
</p>

### 3D Model

<p align="center">
  <img src="assets/hardware/3d-f.jpg" alt="PCB Front" width="48%">
  <img src="assets/hardware/3d-b.jpg" alt="PCB Back" width="48%">
</p>

### Assembly

<p align="center">
  <img src="assets/hardware/real-a.jpg" alt="Assembly View A" width="31%">
  <img src="assets/hardware/real-b.jpg" alt="Assembly View B" width="31%">
  <img src="assets/hardware/real-c.jpg" alt="Assembly View C" width="31%">
</p>

## Firmware

### Config and build

<p align="center">
  <img src="assets/firmware/config.gif" alt="PCB Front" width="48%">
  <img src="assets/firmware/build.gif" alt="PCB Back" width="48%">
</p>

### Runtime

![Runtime](assets/firmware/run-time.gif)

## App

### Demo

<p align="center">
  <img src="assets/app/app-1.gif" alt="App Demo 1" width="23%">
  <img src="assets/app/app-2.gif" alt="App Demo 2" width="23%">
  <img src="assets/app/app-3.gif" alt="App Demo 3" width="23%">
  <img src="assets/app/app-4.gif" alt="App Demo 4" width="23%">
</p>

## Unity Dashboard

The Unity visualization project lives in [`unity-dashboard/`](unity-dashboard/). See its [setup guide](unity-dashboard/README.md) for the required Unity version, EasyChart dependency, backend configuration, and run instructions.

## Contributing

- Read [AGENTS.md](AGENTS.md) before making changes.
- For structural work, also read `docs/ARCHITECTURE.md`, `docs/MQTT_PROTOCOL.md`, and `docs/API_REFERENCE.md`.
- Keep changes narrow, update matching docs when contracts change, and run the narrowest verification for the area you touched.

## License

MIT. See [LICENSE.md](LICENSE.md).
