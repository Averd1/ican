# iCan Eye — XIAO ESP32-S3 Camera Module

## Links

- [Production Docs](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/#for-seeed-studio-xiao-esp32s3)
- [Camera Reference](https://github.com/limengdu/SeeedStudio-XIAO-ESP32S3-Sense-camera)
- [ESP TFLite Micro](https://github.com/espressif/esp-tflite-micro)
- [Google LiteRT](https://ai.google.dev/edge/litert)

---

## BLE Camera — Quick Start

Captures a JPEG photo on the XIAO ESP32-S3 Sense and transfers it to your computer
over Bluetooth Low Energy using a reliable chunked protocol.

### Files

| File | Description |
|------|-------------|
| `arduino_examples/ble_camera.ino` | V1 firmware — fixed resolution (QVGA 320x240) |
| `test_scripts/receive_photo.py` | V1 receiver — single capture |
| `arduino_examples/ble_camera_v2.ino` | **V2 firmware** — selectable quality profiles |
| `test_scripts/receive_photo_v2.py` | **V2 receiver** — interactive, multi-capture |
| `include/camera_pins.h` | Camera GPIO pin definitions (shared) |

### Quality Profiles (V2)

| # | Name | Resolution | JPEG Quality | Est. Size | Est. Transfer |
|---|------|-----------|-------------|-----------|--------------|
| 0 | FAST | 320×240 | 15 | ~3-5 KB | ~2s |
| 1 | BALANCED | 640×480 | 12 | ~15-25 KB | ~8s |
| 2 | QUALITY | 800×600 | 10 | ~30-50 KB | ~15s |
| 3 | MAX | 1600×1200 | 10 | ~80-150 KB | ~45s |

> **Note:** The OV2640 sensor maxes out at 1600×1200 (UXGA). The XIAO ESP32-S3 Sense has
> 8MB PSRAM which is used for frame buffers at higher resolutions.

### 1. Flash the ESP32

1. Install the **ESP32 board package** in Arduino IDE  
   *(Board Manager → search "esp32" → install by Espressif)*
2. Select board: **XIAO_ESP32S3**
3. Open `arduino_examples/ble_camera.ino`
4. **Important:** Copy `include/camera_pins.h` into the same folder as the `.ino`,  
   or put it in the Arduino `libraries/` include path
5. Upload

The Serial Monitor (115200 baud) should show:
```
=== iCan Eye BLE Camera ===
[CAM] Camera initialized
[CAM] Warm-up complete
[BLE] Advertising as 'XIAO_Camera' — waiting for connection...
```

### 2. Receive Photos (Python)

```bash
pip install bleak
```

**V1 (single capture):**
```bash
python test_scripts/receive_photo.py
```

**V2 (interactive, recommended):**
```bash
# Start with BALANCED profile, interactive mode
python test_scripts/receive_photo_v2.py

# Start with QUALITY profile
python test_scripts/receive_photo_v2.py --profile 2

# Single MAX capture then exit
python test_scripts/receive_photo_v2.py --profile 3 --once
```

V2 interactive commands:
| Input | Action |
|-------|--------|
| `Enter` | Capture a photo |
| `0`-`3` | Switch quality profile |
| `q` | Quit |

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Device not found** | Ensure ESP32 is powered, check Serial Monitor for advertising message, enable Bluetooth on PC |
| **CRC mismatch** | Usually a one-off BLE glitch — the script retries automatically |
| **Image too dark/bright** | The firmware warms up the sensor on boot. Wait a few seconds after power-on before capturing |
| **Compile error:** `camera_pins.h not found` | Copy the file into the same folder as `ble_camera.ino` |
| **Compile error:** `esp_rom_crc.h not found` | Update your ESP32 board package to the latest version |

### Protocol Overview

```
Control Char (notify):  ESP32 → PC     "SIZE:12345"   (image size in bytes)
                        ESP32 → PC     "CRC:AABBCCDD" (CRC32 hex)
                        ESP32 → PC     "END:42"       (total chunk count)
Control Char (write):   PC → ESP32     "CAPTURE"      (trigger photo)
Data Char (notify):     ESP32 → PC     [2B seq#][180B data]  (image chunks)
```

Each data chunk has a 2-byte little-endian sequence number so the receiver can
detect dropped or reordered packets.
