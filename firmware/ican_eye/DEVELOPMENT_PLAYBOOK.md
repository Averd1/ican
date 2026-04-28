# iCan Eye Firmware Development Playbook

## Purpose
This document captures the development setup, daily workflow, and engineering philosophy for the **iCan Eye (XIAO ESP32-S3 Sense)** module. It complements the iCan Cane playbook.

## Current Setup

### Workspace and Structure
The project is built as a standard PlatformIO application:
- **`lib/`**: Contains modular firmware systems (e.g., `camera`, `ble_eye`).  These must compile independently of `main.cpp`.
- **`src/`**: Contains entry points. `main.cpp` is the full firmware. The `*_test_main.cpp` files are isolated test environments.
- **`include/`**: Contains shared board-level definitions (`camera_pins.h`).
- **`test_scripts/`**: Contains Python helpers used by the host PC to act as a BLE client (e.g., `receive_photo_v2.py`).

### Supported Target
- **Board:** Seeed XIAO ESP32-S3 Sense with camera module and 8MB PSRAM.

### App Modes (Environments)
Always use explicit environments when building/uploading to avoid compiling the wrong file.

- **`xiao_esp32s3`**: The full firmware integrating camera and BLE.
- **`test_camera`**: Isolated test. Takes photos and prints stats to Serial. No BLE overhead.
- **`test_ble_stream`**: Isolated test. Sends a dummy 30KB buffer over BLE to test chunking and throughput without camera dependencies.

## Standard Command Workflow (Windows)

Run these from the `firmware/ican_eye/` directory.

### Build
- Full firmware: `py -m platformio run -e xiao_esp32s3`
- Camera test: `py -m platformio run -e test_camera`
- BLE test: `py -m platformio run -e test_ble_stream`

### Upload
Append `-t upload` and your COM port:
- `py -m platformio run -e xiao_esp32s3 -t upload --upload-port COM4`

### Monitor
- `py -m platformio device monitor -p COM4 -b 115200`
*(Remember to close the monitor before uploading to avoid COM port locks).*

## BLE Interaction Testing

Once the full firmware (or BLE test firmware) is flashed, use the Python test scripts to verify the BLE data stream:

```bash
cd test_scripts/
python receive_photo_v2.py
```
*Note: Requires `bleak` (`pip install bleak`).*

## Adding New Features (Template)

When adding functionality (e.g., local TFLite object detection, SD card logging):
1. **Create a module:** e.g., `lib/edge_ai/edge_ai.h`. Keep the public API minimal.
2. **Create a test entry:** `src/edge_ai_test_main.cpp` that feeds dummy data to your module.
3. **Add a platformio.ini environment:** `[env:test_edge_ai]` specifying `build_src_filter = +<edge_ai_test_main.cpp> -<main.cpp>`.
4. **Validate:** Build, flash, and verify your module works in isolation.
5. **Integrate:** Wire it into `src/main.cpp`.

## Memory & PSRAM Guidelines
- The XIAO ESP32-S3 has 8MB of PSRAM.
- Large buffers (like camera framebuffers and BLE transmit buffers) should be allocated in PSRAM using `ps_malloc()` or by relying on ESP-IDF drivers configured to use PSRAM.
- When passing arrays across BLE functions, be mindful of the MTU size and chunking logic (see `ble_eye.cpp`).

## Definition of Done
A feature module is "done" when:
- The isolated test environment compiles and passes over Serial.
- Full firmware integration works without causing camera frame buffer overflows (FB-OVF) or BLE disconnects.
- The shared BLE protocol (`shared/ble_protocol.h`) remains backward-compatible with the Flutter application.
