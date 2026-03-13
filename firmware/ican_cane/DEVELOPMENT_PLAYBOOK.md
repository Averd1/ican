# iCan Cane Firmware Development Playbook

## Purpose
This document captures the current development setup, daily workflow, and engineering philosophy used for module testing and integration.

Use this as the default approach when adding new modules (for example: sensors, haptics, BLE features, GPS enhancements) and when preparing data paths for mobile app integration.

## Current Setup

### Workspace and Structure
- Project root: this PlatformIO firmware folder.
- Modules live under lib/ as independent components.
- Entry points live under src/.
- Shared protocol/header material can be included with build flags.

### Board Strategy
The project supports two microcontroller targets in PlatformIO environments:
- Arduino Nano ESP32
- ESP32-WROOM-32 (esp32dev definition)

This allows board switching without changing source logic.

### App Modes
The project uses separate build environments for:
- Full firmware mode: main app behavior.
- Module test mode: isolated test app for one module.

For GPS specifically:
- Full firmware entries include src/main.cpp.
- GPS-only test entries include src/gps_test_main.cpp and exclude src/main.cpp.

This separation is intentional and should be repeated for future modules.

## Development Philosophy

### 1) Isolate First, Integrate Second
- Build and validate each module in a focused test environment first.
- Confirm sensor I/O, parsing, timing, and stability independently.
- Integrate into the full firmware only after module test confidence is high.

### 2) Keep Hardware Variation in Config, Not in Logic
- Board differences should mostly live in PlatformIO environments and pin constants.
- Business logic should remain as board-agnostic as practical.

### 3) Prefer Repeatable Loops
- Use short build-upload-monitor loops.
- Keep output human-readable for field debugging.
- Use explicit environment names so the active target is obvious.

### 4) Preserve Non-Blocking Runtime Behavior
- Polling/parsing functions should stay lightweight.
- Avoid long blocking delays in loop paths.
- Prefer timing windows (millis) over delay for recurring tasks.

### 5) Treat Observed Data as Ground Truth
- Values like satellite count are measured outcomes, not directly settable constants.
- Improve quality by hardware conditions and module configuration, not by forcing values.

## Standard Command Workflow (Windows)
Run commands from the firmware project folder.

### Build
- WROOM GPS test: py -m platformio run -e test_gps_wroom32
- Nano GPS test: py -m platformio run -e test_gps

### Upload
- WROOM GPS test: py -m platformio run -e test_gps_wroom32 -t upload --upload-port COM4
- Nano GPS test: py -m platformio run -e test_gps -t upload --upload-port COM4

### Monitor
- py -m platformio device monitor -p COM4 -b 115200

Note: On this machine, PlatformIO is available through py -m platformio even when pio is not available.

## Safe Serial-Port Sequence
To avoid COM busy/permission errors:
1. Stop monitor first (Ctrl+C).
2. Upload firmware.
3. Start monitor after upload succeeds.
4. If port errors continue, unplug/replug and rerun device list.

## Module Addition Pattern (Template)
When adding a new module, follow this sequence:
1. Create module folder under lib/<module_name>/ with .h and .cpp.
2. Add a focused test entry point in src/<module_name>_test_main.cpp.
3. Add one or more PlatformIO test environments that compile only the test file.
4. Add serial output that proves module health and key telemetry.
5. Validate on both boards if module is board-dependent.
6. Integrate module into full firmware loop.
7. Keep test environment for regression checks (do not delete it).

## Naming Conventions
- Environment names:
  - full firmware: board-specific name
  - test apps: test_<module> and test_<module>_<board>
- Test entry files: src/<module>_test_main.cpp
- Module API: minimal public surface in header, implementation details in cpp.

## Integration Readiness for Mobile App
Before exposing module data to Flutter/app layers:
1. Confirm stable, timestamped, structured telemetry from firmware.
2. Define update rate and units explicitly.
3. Decide validity rules (for example: min satellites for trusted GPS).
4. Add error states and fallback states in telemetry contract.
5. Test behavior under loss-of-signal and noisy conditions.

## Definition of Done for a Module
A module is considered done when:
- Isolated test environment passes repeatedly.
- Full firmware integration works without regressions.
- Logs are clear enough for quick field diagnosis.
- Data contract for upper layers is documented.
- Board-switch build paths remain green.

## Troubleshooting Quick Reference
- Build succeeds, upload fails with busy COM: close monitor and retry upload.
- GPS has fix but low satellite count: improve sky view, antenna, power, warm-start conditions.
- Environment confusion: verify exact -e environment name before build/upload.

## Recommended Next Step for Future Work
For each new hardware module, create and keep a dedicated test environment from day one. This keeps integration velocity high and debugging cost low as the system grows.
