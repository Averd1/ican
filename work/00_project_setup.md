# 00 — Project Setup: Monorepo Structure & Shared BLE Protocol

## What Was Done
Established the monorepo layout separating the Flutter app (`lib/`), firmware (`firmware/`), and shared protocol (`protocol/`). Created the shared BLE protocol definition as a YAML file and mirrored it into a C++ header and Dart constants file. Built out PlatformIO firmware skeletons for both the iCan Cane (Arduino Nano ESP32) and iCan Eye (XIAO ESP32-S3). Created the Flutter app foundation with modular services, models, and screens.

## Files Created

### Protocol (single source of truth)
- `protocol/ble_protocol.yaml` — UUIDs, opcodes, packet formats
- `firmware/shared/ble_protocol.h` — C++ mirror (enums, packed structs)
- `lib/protocol/ble_protocol.dart` — Dart mirror (constants, codec classes)

### Firmware — iCan Cane
- `firmware/ican_cane/platformio.ini` — PlatformIO config
- `firmware/ican_cane/src/main.cpp` — Entry point with sensor polling, haptic dispatch, BLE nav
- `firmware/ican_cane/lib/haptics/haptics.h` + `.cpp` — DRV2605L wrapper
- `firmware/ican_cane/lib/sensors/sensors.h` + `.cpp` — LiDAR, ultrasonic, IMU
- `firmware/ican_cane/lib/ble_comm/ble_comm.h` + `.cpp` — NimBLE peripheral

### Firmware — iCan Eye
- `firmware/ican_eye/platformio.ini` — PlatformIO config
- `firmware/ican_eye/src/main.cpp` — Camera capture, dual-pipeline BLE (instant text + JPEG stream)

### Flutter App
- `lib/main.dart` — App entry point (replaced boilerplate)
- `lib/core/theme.dart` — Accessibility dark theme
- `lib/core/app_router.dart` — Named routes
- `lib/services/ble_service.dart` — BLE scan/connect/read/write
- `lib/services/tts_service.dart` — Text-to-Speech
- `lib/services/stt_service.dart` — Speech-to-Text
- `lib/services/nav_service.dart` — Mapbox directions stub
- `lib/models/device_state.dart` — Device state tracking
- `lib/screens/home_screen.dart` — Main screen with mic button
- `lib/screens/nav_screen.dart` — Turn-by-turn navigation screen

### Files Modified
- `pubspec.yaml` — Added `flutter_reactive_ble`, `flutter_tts`, `speech_to_text`, `provider`

## Rationale
**Monorepo**: Keeping firmware and app in one repo ensures protocol changes are committed atomically — no version drift between the two sides.

**YAML-first protocol**: Defining UUIDs, opcodes, and packet formats in a single YAML file prevents mismatches. The C++ header and Dart constants are hand-mirrored for now; code generation can be added later.

**PlatformIO over Arduino IDE**: PlatformIO supports multi-project repos with per-project `platformio.ini`, library dependency management (`lib_deps`), and CLI builds — critical for a project with two separate microcontroller targets sharing a common header.
