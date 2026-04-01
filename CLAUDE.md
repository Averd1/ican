# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**iCan** is an assistive navigation system for visually impaired users. It is a monorepo combining:
- A **Flutter mobile app** (iOS/Android) for voice-driven navigation and scene description
- **ESP32 firmware** for two hardware modules: the iCan Cane (sensors + haptics) and iCan Eye (camera)

All three layers communicate over BLE 5.0.

---

## Commands

### Flutter App

```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device/emulator
flutter test             # Run all tests
flutter test test/widget_test.dart  # Run a single test file
flutter build apk        # Build Android APK
```

### Firmware — iCan Cane (Arduino Nano ESP32)

```bash
cd firmware/ican_cane
pio run -e nano_esp32              # Build production firmware
pio run -e test_gps                # Build GPS test firmware
pio device monitor -b 115200       # Serial monitor
pio run -e nano_esp32 --target upload  # Flash device
```

### Firmware — iCan Eye (XIAO ESP32-S3)

```bash
cd firmware/ican_eye
pio run -e xiao_esp32s3            # Build production firmware
pio run -e test_camera             # Camera initialization test
pio run -e test_ble_stream         # BLE image streaming test
pio run -e test_blink              # GPIO blink test
pio device monitor -b 115200
pio run -e xiao_esp32s3 --target upload
```

---

## Architecture

### System Overview

```
iPhone/Android (Flutter App)
  ├── Voice I/O (STT/TTS)
  ├── Navigation (Mapbox → BleService → Cane haptics)
  └── Vision (BLE image stream → local VLM or Vertex AI → TTS)
           │ BLE 5.0                    │ BLE 5.0
  iCan Cane (Nano ESP32)         iCan Eye (XIAO ESP32-S3)
  ├── Sensors: TF Luna LiDAR,          ├── OV2640 camera (PSRAM)
  │   2x Ultrasonic, LSM6DSOX IMU      ├── TFLite Micro (instant labels)
  └── Haptics: 3x DRV2605L motors      └── BLE chunked JPEG streaming
```

### BLE Protocol (Single Source of Truth)

`protocol/ble_protocol.yaml` is the canonical definition. It is mirrored in:
- **C++**: `firmware/shared/include/ble_protocol.h`
- **Dart**: `lib/protocol/ble_protocol.dart`

**Always update the YAML first, then the C++ header, then the Dart file.** Never invent constant names — verify exact identifiers in `ble_protocol.dart` before using them (e.g., `BleServices.caneServiceUuid`, not `BleServices.icanCaneUuid`).

Key UUIDs:
- Cane service: `10000001-1000-1000-1000-100000000000`
- Eye service: `20000001-2000-2000-2000-200000000000`

Telemetry packet (6 bytes, little-endian): `flags | pulse_bpm | battery_% | yaw_angle (int16 × 10) | reserved`

Image stream packet (240 bytes max): `seq_num (2B) | total_chunks (2B) | checksum (1B XOR) | payload (≤235B)`

### Flutter App (`lib/`)

- **`services/ble_service.dart`** — Singleton; scans/connects to both devices, exposes `obstacleStream`, `telemetryStream`, `instantTextStream`, reassembles chunked image frames
- **`services/vertex_ai_service.dart`** — Fallback cloud vision when local VLM is unavailable
- **`protocol/ble_protocol.dart`** — Dart codec mirroring the YAML spec; use these constants everywhere
- **`models/device_state.dart`** — `ChangeNotifier` for app-wide device state
- **`core/app_router.dart`** — Named routes: splash → role_selection → home → nav → caretaker_dashboard
- State management: `Provider` + `ChangeNotifier`

### Firmware (`firmware/`)

Each subsystem is isolated in `lib/` with a clean `.h` interface:

| Module | Subsystems |
|--------|-----------|
| ican_cane | `ble_comm/`, `haptics/`, `sensors/`, `gps/` |
| ican_eye | `ble_eye/`, `camera/` |

Main loop runs at **20 Hz** sensor polling, **5 Hz** telemetry transmission. Obstacle threshold: `OBSTACLE_THRESHOLD_CM = 80`.

**Haptic priority**: obstacle avoidance always overrides GPS navigation commands.

---

## Coding Principles

### C++ (Firmware)

**Include ordering** — always: Arduino framework → third-party → local:
```cpp
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include "sensors.h"
```

**Use `<stdint.h>`, not `<cstdint>`** in `.h` headers — `<cstdint>` is C++ and clangd cannot resolve it without the ESP32 sysroot.

**Avoid `<math.h>` / `sqrt()`** on Windows builds — use squared comparisons instead (`x*x + y*y + z*z < threshold*threshold`).

### Dart (Flutter)

Verify constant names against `lib/protocol/ble_protocol.dart` before use — invented names will compile but produce runtime BLE failures.

### IDE / Build Tooling

**Clangd cross-compilation**: if clangd crashes on Xtensa flags (`-mlongcalls`, `-fstrict-volatile-bitfields`), add a `.clangd` file:
```yaml
CompileFlags:
  Remove:
    - -mlongcalls
    - -fstrict-volatile-bitfields
```

**Android Gradle / Java version mismatch**: if the build fails with Java 25, point Gradle to Android Studio's bundled JDK:
```properties
# android/gradle.properties
org.gradle.java.home=C:/Program Files/Android/Android Studio/jbr
```

**Windows BLE fallback**: `BleService` has a hardcoded fallback device ID `'90:70:69:12:53:BD'` for Windows desktop testing.

---

## Key Documentation

- `iCan.md` — Hardware architecture, component specs, design decisions
- `development_plan.md` — 5-week phased roadmap (hardware → comms → app core → complex logic → field testing)
- `coding-principles/` — Four detailed documents on the principles above
- `firmware/ican_cane/DEVELOPMENT_PLAYBOOK.md` — Cane firmware development guide
