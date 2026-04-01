# iCan Eye BLE Diagnostic Report

This report summarizes the hardware and software states of the **Seeed Studio XIAO ESP32-S3** firmware and the corresponding Windows Flutter app. It details the steps taken to resolve the "invisible" BLE broadcasting issue, the boot loop crashes, and what still needs to be solved.

---

## 1. The Core Issue
The Flutter Windows application successfully launches and scans for devices, but the XIAO ESP32-S3 board (iCan Eye) is **completely absent from the airwaves**. 

Even an independent raw Python `BleakScanner` script running on the host machine confirms that the physical MAC address of the chip (`90:70...`) never broadcasts a single discovery packet. 

## 2. Firmware Diagnostics & Boot Loops (Fixed)
The native USB CDC serial monitor built into the ESP32-S3 fails to output any logs because the chip was kernel-panicking and rebooting *before* Windows could physically open the virtual COM port. 
* To bypass this "blind spot", physical LED diagnostic markers (`digitalWrite(LED_BUILTIN...)`) were injected into the boot sequence of `ble_stream_test_main.cpp`. 
* **The Culprit:** The firmware was hard-crashing instantly during `initBleEye()`. 
* **The Cause:** The code was written for the NimBLE 1.x API, but PlatformIO pulled `NimBLE-Arduino@2.4.0` (which fundamentally changed its `NimBLEServer::start()` requirements, leading to null-pointer faults when advertising was called). Additionally, `setPower(ESP_PWR_LVL_P9)` triggers kernel panics on ESP32-S3 Core 3.x frameworks.

**Resolution:**
We successfully downgraded the `platformio.ini` dependency to `NimBLE-Arduino@1.4.1`, removed the unsupported `setPower()` and `enableScanResponse(true)` APIs, and refactored the callbacks. 
**Result:** The LED diagnostic sequence now successfully completes and turns off, proving the firmware *survives* BLE initialization and is actively spinning in `loop()`. The firmware is stable.

## 3. The Unresolved "Silent Radio" Bug
Despite the firmware successfully executing `NimBLEDevice::getAdvertising()->start()` without crashing, the physical radio PHY layer is not emitting RF signals. 

This usually points to one of two things:
1. **Disconnected Physical Antenna (Highly Likely):** The Seeed Studio XIAO ESP32-S3 Sense **does not possess an onboard PCB antenna**. It requires the separate external U.FL stick-on antenna included in the bag to be pushed onto the gold IPEX connector. If this is missing or loose, the broadcast range is literally zero centimeters.
2. **Arduino Core 3.x vs NimBLE PHY Bug:** The ESP32-S3 Arduino 3.0.x core (built on ESP-IDF 5.1) has known initialization race conditions with older NimBLE 1.4.1 libraries where the Bluetooth baseband hardware is never properly powered on despite the software reporting success.

## 4. Flutter Windows Wrapper Bug (Fixed)
The Flutter application originally failed to scan at all on Windows. The `adapterState.first` command returned `BluetoothAdapterState.unknown` instantly because the asynchronous WinBle API had not finished warming up.
* **Resolution:** Refactored `ble_service.dart` to use a 3-second `.where((s) => s == BluetoothAdapterState.on).first` timeout loop. The scan now triggers smoothly on Windows laptops.

---

## Next Steps for the Firmware Developer
1. **Verify the Hardware Antenna:** Physically inspect the XIAO ESP32-S3 board and ensure the U.FL IPEX antenna is firmly secured to the board. 
2. **Bypass USB CDC for Logs:** Attach an FTDI / USB-to-UART adapter to the physical `TX` (D6) and `RX` (D7) pins of the XIAO. This is the *only* way to see the raw bootloader `panic` strings if the chip continues to act erratically.
3. **Migrate to BLE Arduino Core:** If the NimBLE library continues to fail silently on the S3, migrate `ble_eye.cpp` back to the standard ESP32 `BLEDevice::` library, which has official first-party support on Arduino Core 3.x and ESP-IDF 5.1.
