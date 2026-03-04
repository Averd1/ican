# 01 — BLE Communication Setup & Testing

## What Was Done
Planned and documented the approach for establishing Bluetooth Low Energy (BLE) communication between the ESP32 (Server) and the Flutter app (Client) using `NimBLE` for C++ and `flutter_blue_plus` for Dart.

## Files Modified
### Flutter App
- `pubspec.yaml` — Swapped `flutter_reactive_ble` for `flutter_blue_plus` dependency.
- `lib/services/ble_service.dart` — Fully implemented BLE scanning, connection, and characteristics subscription logic (RX/TX data streams) using `flutter_blue_plus`. Fixed UUID constant references to correctly map to `ble_protocol.dart`.

*(Note: The ESP32 firmware files `firmware/ican_cane/lib/ble_comm/ble_comm.h` and `.cpp` were reviewed and found to be already correctly implemented with `NimBLE`, requiring no changes).*

## Reflection & Rationale
- **NimBLE over standard BLEDevice**: `NimBLE` is significantly more RAM-friendly and faster on the ESP32, leaving crucial memory available for other sensor and ML tasks.
- **flutter_blue_plus**: Chosen as the Dart BLE client because it's actively maintained and integrates well with both iOS and Android.
- **Connection Approach**: The ESP32 hosts a Service with TX (Notify) and RX (Write) characteristics. The app scans for the specific device name/UUID, connects, and subscribes to the TX stream while sending commands to the RX characteristic. For high bandwidth (like iCan Eye images), L2CAP CoC with MTU adjustments will be necessary.

## How to Test / Demo Setup

### 1. Firmware (ESP32)
- Flash the ESP32 via PlatformIO.
- Open the Serial Monitor (115200 baud). You should see "Waiting for client connection...".
- The ESP32 is now advertising its BLE service.

### 2. App (Flutter)
- Ensure the physical testing phone has Bluetooth turned ON and Location/Nearby Devices permissions granted.
- **Note**: BLE cannot be effectively tested on an iOS/Android emulator. A physical device is required.
- Run the Flutter app: `flutter run -d <your-device-id>`.

#### [MODIFY] `firmware/ican_cane/lib/ble_comm/ble_comm.cpp`
- Implement the BLE server initialization logic.
- Implement `onConnect` and `onDisconnect` callbacks to handle connection state and resume advertising on disconnect.
- Implement `onWrite` callback on the RX characteristic to process incoming navigation commands from the Flutter app.
- Provide a method to send simulated telemetry data over the TX characteristic.
- **Update to NimBLE 2.0 API**: Use `enableScanResponse()`, `getValue().size()`, and ensure `setValue()` overloads are correctly used.

### 3. Verification Steps
1. In the app, trigger the connection routine.
2. The app should discover the ESP32 and connect.
3. Observe the ESP32 Serial Monitor: It should reflect a successful connection.
4. Sending a mock navigation command from the app should print on the ESP32's Serial Monitor.
5. Telemetry data (e.g., heartbeat/fall stub data) sent from the ESP32 should appear in the Flutter app's debug console or UI.

## References
- [NimBLE ESP32 Documentation](https://docs.arduino.cc/libraries/nimble-arduino/)
- [flutter_blue_plus Documentation](https://pub.dev/packages/flutter_blue_plus)