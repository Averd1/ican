# ProtoSmartCane v2.0 - Deployment Verification Checklist

Use this document to verify your hardware integration and validate the firmware before field deployment.

---

## ✓ Phase 1: Pre-Assembly Verification

### Hardware Bill of Materials

- [ ] ESP32 Nano (Arduino compatible)
- [ ] LSM6DSOX IMU module
- [ ] TF Luna LiDAR module
- [ ] 2× URM37 Ultrasonic modules
- [ ] Pulse Sensor (analog HRM)
- [ ] TSL2561 Ambient Light Sensor (NEW)
- [ ] DRV2605L Haptic Driver (NEW)
- [ ] High-power LED (RGB or white)
- [ ] PCA9548A I2C Multiplexer
- [ ] 660mAh LiPo battery
- [ ] Voltage divider resistors (R1=11kΩ, R2=3.3kΩ)
- [ ] I2C pull-up resistors (4.7kΩ SDA/SCL, ×2)

### Tools Required

- [ ] Multimeter
- [ ] I2C scanner tool (or PlatformIO)
- [ ] USB-C cable for ESP32 flashing
- [ ] Arduino IDE or VS Code + PlatformIO

---

## ✓ Phase 2: Hardware Assembly

### I2C Bus Setup

1. [ ] Connect all I2C devices to dedicated SDA/SCL bus with pull-ups
2. [ ] Route through PCA9548A multiplexer @ 0x70
3. [ ] Test with i2cdetect:

```bash
i2cdetect -y 1
```

Add expected addresses to checklist:

- [ ] **0x10** - TF Luna LiDAR
- [ ] **0x11** - URM37 Ultrasonic (×2, may need address staggering)
- [ ] **0x39** - TSL2561 Light Sensor (NEW)
- [ ] **0x5A** - DRV2605L Haptic Driver (NEW)
- [ ] **0x6A** - LSM6DSOX IMU (behind mux)
- [ ] **0x70** - PCA9548A Multiplexer

### Power & Signal Lines

1. [ ] **Battery Connection**
   - [ ] LiPo + → ESP32 VCC
   - [ ] LiPo - → ESP32 GND
   - [ ] Verify voltage: 3.7V nominal (3.0-4.2V range)

2. [ ] **Voltage Divider Calibration**
   - [ ] R1 (11kΩ) between battery + and GPIO 26
   - [ ] R2 (3.3kΩ) between GPIO 26 and GND
   - [ ] Measure with multimeter:
     - At battery: `(GPIO26_V + GND) × (R1+R2)/R2 = Battery_V`
     - Should read 3.0-4.2V for LiPo

3. [ ] **LED Connection**
   - [ ] Connect to GPIO 11 with current-limiting resistor
   - [ ] Verify with PWM test (see Phase 4)

4. [ ] **Pulse Sensor**
   - [ ] Connect data line to A0 (GPIO 26)
   - [ ] Verify readings in serial monitor

---

## ✓ Phase 3: Software Compilation

### Build Environment Setup

1. [ ] Install PlatformIO:
   ```bash
   pip install platformio
   ```

2. [ ] Navigate to firmware directory:
   ```bash
   cd firmware/protosmart_cane
   ```

3. [ ] Build for Nano ESP32:
   ```bash
   pio run -e nano_esp32
   ```

### Expected Build Output

```
Building in release mode
...
=== [SUCCESFUL] took X.XX seconds ===
```

### Common Build Errors & Solutions

| Error | Cause | Fix |
|-------|-------|-----|
| `#include not found` | Wrong include path | Verify lib/ folder structure |
| `undefined reference` | Missing .cpp implementation | Check all .h have matching .cpp |
| `-mlongcalls` flag error | Xtensa compiler issue | See `.clangd` cross-compilation config |
| `cstdint` error | Wrong C++ header | Use `<stdint.h>` instead |

---

## ✓ Phase 4: Flash & Initial Testing

### Upload Firmware

1. [ ] Connect ESP32 via USB-C
2. [ ] Flash device:
   ```bash
   pio run -e nano_esp32 --target upload
   ```
3. [ ] Expected output:
   ```
   Chip is ESP32-D0WDQ6 (revision 3)
   Features: WiFi, BT, Dual Core
   ...
   Wrote X bytes in Y.Z seconds
   ```

### Serial Monitor Check

1. [ ] Open serial monitor:
   ```bash
   pio device monitor -b 115200
   ```

2. [ ] Verify initial startup message (first 5 seconds):
   ```
   === ProtoSmartCane Firmware v1.0 ===
   Initializing system...
   Battery: 3.85V (95%) - 2.8 hours remaining
   System initialization complete!
   Mode: NORMAL | Battery: Monitoring | Sensors: Active
   ```

3. [ ] Check for errors/warnings:
   - [ ] No "sensor initialization failed" messages
   - [ ] Battery voltage in expected range (3.0-4.2V)
   - [ ] Runtime estimate > 0 minutes
   - [ ] No I2C errors

---

## ✓ Phase 5: Functional Verification

### 5.1 Battery Monitoring Test

**Expected:** Battery voltage displays 3.0-4.2V with runtime estimate

1. [ ] Measure battery voltage with multimeter
2. [ ] Compare with serial output
3. [ ] Verify runtime calculation:
   - [ ] NORMAL: ~2.8 hours
   - [ ] Battery <20%: Shows 6.9+ hours with LOW_POWER mode

---

### 5.2 Fall Detection Test

**Expected:** 0-3s buzzer/LED/haptic continuous, then 3-30s pulsed, then timeout

```
Test: Simulate safe fall (accelerate downward, then decelerate sharply)
  Accelerometer reading: ax < -10 m/s² (freefall)
  Then gz > +25 m/s² (impact confirming fall, not just jump)

Response Timeline:
  0-3s:    LED=255, Haptic=255, Buzzer=HIGH
  3-30s:   LED pulse, Haptic pulse (100ms interval)
  >30s:    System silent (but ready for next emergency)
```

Serial output should show:
```
EMERGENCY MODE: Fall/IMU failure detected
EMERGENCY ACTIVE: 0s (max intensity)
EMERGENCY ACTIVE: 5s (pulsing)
EMERGENCY CLEARED: Returning to normal operation
```

**Verification Checklist:**
- [ ] Buzzer ON for 0-3 seconds
- [ ] Buzzer PULSES for 3-30 seconds
- [ ] Buzzer OFF after ~30 seconds
- [ ] LED brightness follows same pattern
- [ ] Haptic vibration intensity matches (255 during max, pulsed after)
- [ ] Serial logs confirm emergency state transitions

---

### 5.3 Obstacle Detection Test

**Expected:** LED + Haptic scale with distance

Set LiDAR at varying distances, verify feedback:

| Distance | LED Brightness | Haptic Intensity | Feedback Feel |
|----------|-----------------|------------------|---------------|
| 100cm | 150 | 50 | Gentle pulse |
| 60cm | 200 | 150 | Medium pulse |
| 30cm | 255 | 255 | Strong rapid pulse |

Serial output:
```
OBJECT_FAR: LED 150, Haptic 50 @ 300ms
OBJECT_NEAR: LED 200, Haptic 150 @ 150ms
OBJECT_IMMINENT: LED 255, Haptic 255 @ 50ms
```

**Verification:**
- [ ] LED gradually brightens as obstacle approaches
- [ ] Haptic vibration increases in intensity
- [ ] Pulse frequency increases (longer intervals → shorter intervals)
- [ ] Response time <100ms

---

### 5.4 Low-Light LED Activation Test

**Expected:** LED auto-activates when <100 lux ambient light

Test procedure:
1. [ ] Cover sensor with hand (simulates darkness, <50 lux)
2. [ ] Observe LED activates at 150+ brightness
3. [ ] Uncover sensor (>100 lux)
4. [ ] Observe LED dims (unless obstacle active)

Serial output:
```
Low-light condition detected: 45 lux
LED illumination enabled (brightness 150)
```

**Verification:**
- [ ] LED on in darkness
- [ ] LED brightness ~150 in low-light
- [ ] LED off in normal light (unless alert)
- [ ] Smooth brightness transitions

---

### 5.5 Sleep Mode Test

**Expected:** System enters CAUTIOUS_SLEEP after 5 min inactivity

Test procedure:
1. [ ] Boot system, keep cane stationary
2. [ ] Monitor serial output for sleep transitions
3. [ ] Wait 5 minutes with no motion (IMU acceleration <2.0 m/s²)

Expected output (approximately at 5:00-5:05):
```
SLEEP MANAGER: Inactivity detected (300s)
SLEEP TRANSITION: NORMAL → CAUTIOUS_SLEEP
Current mode: CAUTIOUS_SLEEP (Power: 31mA)
```

Then wait another 15+ minutes:
```
SLEEP TRANSITION: CAUTIOUS_SLEEP → DEEP_SLEEP
Current mode: DEEP_SLEEP (Power: 10.6mA)
```

**Wake Test:**
4. [ ] Apply sharp motion (shake cane)
5. [ ] Observe exit to NORMAL mode:
```
MOTION DETECTED: Acceleration 3.2 m/s²
SLEEP WAKE: DEEP_SLEEP → NORMAL
```

**Verification:**
- [ ] CAUTIOUS_SLEEP entered after ~5 min
- [ ] DEEP_SLEEP entered after ~20 min total
- [ ] Motion (>2.0 m/s²) triggers wake
- [ ] System returns to NORMAL/EMERGENCY appropriately
- [ ] No accidental sleep within 60s of emergency

---

### 5.6 Low-Power Mode Test

**Expected:** System switches to LOW_POWER when battery <20%

1. [ ] Simulate low battery by editing config.h temporarily:
   ```cpp
   #define BATTERY_LOW_THRESHOLD 95  // Force mode change
   ```
2. [ ] Recompile and flash
3. [ ] Monitor serial output:
   ```
   MODE CHANGE: LOW_POWER (Battery low)
   ```
4. [ ] Verify sensor polling rates decrease:
   - [ ] IMU: 20Hz → 10Hz
   - [ ] LiDAR: 25Hz → 12.5Hz
   - [ ] Pulse: 2Hz → 1Hz

---

### 5.7 BLE Telemetry Test (if app available)

**Expected:** Telemetry packet includes runtime estimate

1. [ ] Connect to mobile app
2. [ ] Verify received telemetry includes:
   - [ ] Battery percentage (0-100%)
   - [ ] Estimated runtime (minutes)
   - [ ] Obstacle distance
   - [ ] Heart rate (if pulse sensor)
   - [ ] Emergency status flags

**Verification Checklist:**
- [ ] Telemetry updates at 5Hz (NORMAL) or 20Hz (EMERGENCY)
- [ ] Runtime estimate changes with battery level
- [ ] Values within expected ranges

---

## ✓ Phase 6: Power Consumption Validation

### Measure Current Draw

Use bench power supply with current meter (or ammeter):

| Mode | Expected | Measured | Pass? |
|------|----------|----------|-------|
| NORMAL | 210mA | ___mA | ☐ |
| LOW_POWER | 85mA | ___mA | ☐ |
| EMERGENCY | 420mA | ___mA | ☐ |
| CAUTIOUS_SLEEP | 31mA | ___mA | ☐ |
| DEEP_SLEEP | 10.6mA | ___mA | ☐ |

### Calculate Actual Runtime

Based on measured values:

```
Runtime = 660mAh × 0.9 (efficiency) × 3.7V / (Measured_mA × 60 sec/min)

NORMAL:  660 × 0.9 × 3.7 / (___mA × 60) = ___ hours
```

Compare with estimated values from app/serial:
- [ ] Within ±10% acceptable range

---

## ✓ Phase 7: Field Pre-Deployment

### Final Hardware Check

- [ ] All sensors responding (i2cdetect shows all addresses)
- [ ] Battery voltage 3.6-4.2V (full charge)
- [ ] No visible loose connections
- [ ] LED illuminates smoothly
- [ ] Haptic vibrates on obstacle
- [ ] Serial output shows no errors

### Functional Check (Quick)

- [ ] Power up: No error messages
- [ ] Stationary 1 min: No unexpected alert
- [ ] Gentle motion: Sensors update
- [ ] Cover light sensor: LED activates
- [ ] Reverse logic (expose sensor): LED dims

### Emergency Protocol Briefing

- [ ] User trained on:
  - [ ] Fall detection (3s continuous + 27s pulsed)
  - [ ] Emergency contact procedure
  - [ ] How to cancel alert if false positive
  - [ ] Battery status monitoring

---

## ✓ Phase 8: Field Trial (First 8+ Hours)

### Mission Parameters

- [ ] Duration: 8+ hours continuous operation
- [ ] Environment: Real-world navigation (streets, trails, indoor)
- [ ] User: Trained operator with emergency contact info

### Monitoring During Trial

- [ ] Battery: Does it reach estimated runtime?
- [ ] Falls: Were any accidentally triggered? (false positives?)
- [ ] Feedback: Are vibration/LED patterns clear?
- [ ] Sleep: Did low-power transitions work?
- [ ] BLE: App connection stable?

### Log Data Points

| Time | Mode | Battery | Distance | Heart BPM | Notes |
|------|------|---------|----------|-----------|-------|
| 00:00 | NORMAL | 95% (2.8h) | 0mm | 72 | Start |
| 01:00 | NORMAL | 80% | 400-500mm avg | 75 | Active |
| 04:00 | NORMAL | 50% (1.4h) | Variable | 70-80 | Lunch break |
| 05:00 | NORMAL→CAUTIOUS | 48% | 0mm | 65 | Idle 5min |
| 07:00 | CAUTIOUS→DEEP | 45% (1.3h) | - | 60 | Extended break |
| 08:00 | NORMAL* | 40% (1.2h) | 300-400mm | 75 | Resume walking |

---

## ✓ Troubleshooting During Deployment

### Issue: LED Not Responding

1. [ ] Check GPIO 11 PWM output:
   ```cpp
   pinMode(11, OUTPUT);
   for(int i=0; i<256; i++) {
       analogWrite(11, i);
       delay(5);
   }
   // Should see LED gradually brighten
   ```
2. [ ] Verify I2C driver if using I2C LED control
3. [ ] Check power to LED circuit

### Issue: Haptic Not Vibrating

1. [ ] Verify DRV2605L at 0x5A: `i2cdetect`
2. [ ] Check I2C pull-ups (should be 4.7kΩ)
3. [ ] Measure I2C clock frequency (100-400kHz)
4. [ ] Verify 3.3V power on haptic driver

### Issue: Sleep Mode Never Activates

1. [ ] Ensure system is truly stationary
2. [ ] Verify IMU calibration (at-rest acceleration ≈ 0)
3. [ ] Check no recent emergency (safety check blocks sleep for 60s)
4. [ ] Increase verbosity in serial monitor

### Issue: Battery Runtime Estimate Wrong

1. [ ] Recalibrate voltage divider:
   - Measure actual battery voltage with multimeter
   - Compare to serial output reading
   - Adjust R1/R2 if > 5% error

2. [ ] Verify power profile consumption:
   - Measure actual current with bench supply
   - Compare to config.h values
   - Update if >10% error

---

## ✓ Post-Trial Report

Generate summary:

```
PROTOSMART v2.0 - FIELD TRIAL REPORT
====================================

Trial Date: _______________
Duration: _____ hours
Distance: _____ km
Users: _______________

RESULTS:
✓ Battery Life: Actual ___h vs Estimated ___h (Accuracy: ±_%)
✓ Fall Detection: Triggered __ times (False positives: __)
✓ Obstacle Response: ___/10 feedback clarity rating
✓ Sleep Modes: Functioned correctly: ☐ Yes ☐ No
✓ LED Illumination: Adequate in low-light: ☐ Yes ☐ No
✓ Haptic Feedback: Felt vibrations clearly: ☐ Yes ☐ No

CRITICAL ISSUES:
- [List any failures or safety concerns]

RECOMMENDATIONS:
- [Improvements or tuning needed]

STATUS:
☐ Production Ready
☐ Ready with Minor Fixes
☐ Needs Major Rework
```

---

## Quick Reference

### Key Serial Commands

```bash
# Build & flash
cd firmware/protosmart_cane
pio run -e nano_esp32 --target upload

# Monitor output
pio device monitor -b 115200

# Build only (no flash)
pio run -e nano_esp32

# Check device list
pio device list
```

### Expected Serial Output (DEBUG_MODE enabled)

```
IMU: ax=0.02, ay=0.05, az=9.81 [m/s²]
LiDAR: 350mm | Ultrasonic L/R: 400/420 mm
Pulse: 72 BPM | Battery: 95% (2.8h remaining)
Mode: NORMAL | Sleep: NONE | Situation: NONE
```

### Quick i2cdetect Check

```bash
# On Linux/Mac
i2cdetect -y 1

# On Windows (if i2c-tools installed)
i2cdetect -y 0
```

Expected output (all addresses present):
```
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- -- --
10: 10 -- -- -- -- -- -- -- -- -- 1a -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- 39 -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- 5a -- -- -- -- -- -- -- -- -- --
60: -- -- -- -- -- -- 6a -- -- -- -- -- -- -- -- --
70: 70 -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

---

**Last Updated:** 2024  
**Version:** 2.0 Deployment Checklist  
**Status:** Ready for Field Trial
