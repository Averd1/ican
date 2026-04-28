/*
 * Haptic Driver Implementation (DRV2605L)
 * 3 independent DRV2605 drivers: 
 *   - Channel 0: Left ultrasonic sensor haptic
 *   - Channel 2: Right ultrasonic sensor haptic
 *   - Channel 3: 8x8 sensor haptic
 */

#include "haptic_driver.h"
#include <Wire.h>

// Module-level state variables
uint8_t hapticIntensity = 0;
unsigned long lastHapticPulse = 0;
uint16_t hapticPulseInterval = 0;

// Track state for each haptic driver
struct HapticDriverState {
    bool initialized;
    uint8_t channel;
    unsigned long lastPulse;
    uint16_t pulseInterval;
    uint8_t currentIntensity;
    bool active;
} hapticDrivers[3] = {
    {false, HAPTIC_8X8_CHANNEL, 0, 0, 0, false},
    {false, HAPTIC_RIGHT_ULTRASONIC_CHANNEL, 0, 0, 0, false},
    {false, HAPTIC_LEFT_ULTRASONIC_CHANNEL, 0, 0, 0, false}
};

void hapticDriverInit() {
    // Diagnostic: I2C bus scan to find what devices are present
    if (DEBUG_MODE) {
        Serial.println("=== I2C BUS SCAN (Primary I2C: GPIO11/12) ===");
        Serial.println("Scanning addresses 0x00-0x7F:");
        
        for (uint8_t addr = 0; addr < 128; addr++) {
            Wire.beginTransmission(addr);
            uint8_t result = Wire.endTransmission();
            
            if (result == 0) {
                Serial.print("Device found at 0x");
                if (addr < 0x10) Serial.print("0");
                Serial.println(addr, HEX);
            }
        }
        Serial.println("=== End of scan ===");
    }
    
    // Full mux sweep: detect any DRV2605 on any channel (0-7)
    if (DEBUG_MODE) {
        Serial.println("=== MUX CHANNEL SWEEP FOR DRV2605 (0x5A) ===");
        for (uint8_t ch = 0; ch < 8; ch++) {
            selectMuxChannel(ch);
            Wire.beginTransmission(DRV2605_ADDR);
            uint8_t chResult = Wire.endTransmission();
            Serial.print("Channel ");
            Serial.print(ch);
            Serial.print(": ");
            if (chResult == 0) {
                Serial.println("DRV2605 detected");
            } else {
                Serial.print("no response (err ");
                Serial.print(chResult);
                Serial.println(")");
            }
        }
        Serial.println("=== End channel sweep ===");
    }

    // Initialize all 3 configured DRV2605 drivers
    uint8_t detectedDrivers = 0;
    for (int i = 0; i < 3; i++) {
        HapticDriverState &driver = hapticDrivers[i];
        
        // Select appropriate mux channel
        if (i == DRIVER_8X8) {
            selectHaptic8x8();
        } else if (i == DRIVER_RIGHT_ULTRASONIC) {
            selectHapticRightUltrasonic();
        } else if (i == DRIVER_LEFT_ULTRASONIC) {
            selectHapticLeftUltrasonic();
        }

        // Let mux channel switching settle before probing device on shared bus.
        delay(3);
        
        // Debug: show which channel we're on and attempt to find device
        if (DEBUG_MODE) {
            Serial.print("Haptic init driver ");
            Serial.print(i);
            Serial.print(" (channel ");
            Serial.print(driver.channel);
            Serial.print("): ");
        }
        
        // Check if DRV2605 is present on this channel with retries.
        uint8_t result = 4;
        bool found = false;
        for (uint8_t attempt = 0; attempt < 4; attempt++) {
            Wire.beginTransmission(DRV2605_ADDR);
            result = Wire.endTransmission();
            if (result == 0) {
                found = true;
                break;
            }
            delay(2);
        }
        
        if (found) {
            // Initialize DRV2605L - Set to RTP (real-time playback) mode
            Wire.beginTransmission(DRV2605_ADDR);
            Wire.write(0x01);  // Mode register
            Wire.write(0x05);  // RTP mode
            Wire.endTransmission();
            
            driver.initialized = true;
            detectedDrivers++;

            // Strong startup pulse on each detected driver channel so wiring can be
            // validated without relying on serial output.
            Wire.beginTransmission(DRV2605_ADDR);
            Wire.write(0x02);  // RTP input register
            Wire.write(HAPTIC_STRONG);
            Wire.endTransmission();
            delay(220);
            Wire.beginTransmission(DRV2605_ADDR);
            Wire.write(0x02);  // RTP input register
            Wire.write(0x00);  // stop
            Wire.endTransmission();
            delay(180);
            
            if (DEBUG_MODE) {
                Serial.println("initialized (DRV2605L)");
            }
        } else {
            if (DEBUG_MODE) {
                Serial.print("not found (I2C error code ");
                Serial.print(result);
                Serial.println(")");
            }
        }
    }

    // Physical confirmation code on center disk (works even if serial output is unavailable)
    // Format: preamble (2 long pulses), then 3 slots:
    // slot1=8x8 driver, slot2=right ultrasonic driver, slot3=left ultrasonic driver
    // In each slot: long pulse = detected, short pulse = not detected
    for (uint8_t i = 0; i < 2; i++) {
        digitalWrite(HAPTIC_DISK_PIN, HIGH);
        delay(260);
        digitalWrite(HAPTIC_DISK_PIN, LOW);
        delay(180);
    }

    for (uint8_t i = 0; i < 3; i++) {
        bool ok = hapticDrivers[i].initialized;
        digitalWrite(HAPTIC_DISK_PIN, HIGH);
        delay(ok ? 260 : 80);
        digitalWrite(HAPTIC_DISK_PIN, LOW);
        delay(260);
    }

    // Additional count pulses for quick sanity check
    delay(220);
    for (uint8_t i = 0; i < detectedDrivers; i++) {
        digitalWrite(HAPTIC_DISK_PIN, HIGH);
        delay(100);
        digitalWrite(HAPTIC_DISK_PIN, LOW);
        delay(100);
    }
}

void updateHapticFeedback() {
    // Priority-based policy adapted from detection logic:
    // 1) Head obstacle (8x8 top rows) -> channel 1 only
    // 2) Waist/front obstacle (8x8 lower rows) -> channels 0 + 2 only
    // 3) Left obstacle -> channel 0 only
    // 4) Right obstacle -> channel 2 only
    // Only one source is active at a time, except front which drives both side motors.
    float intensityModifier = (currentMode == LOW_POWER) ? 0.6f : 1.0f;
    unsigned long intervalModifier = (currentMode == LOW_POWER) ? 1.5f : 1.0f;

    enum ActiveSource : uint8_t {
        SOURCE_NONE = 0,
        SOURCE_HEAD,
        SOURCE_FRONT,
        SOURCE_LEFT,
        SOURCE_RIGHT,
    };

    auto isValidDistance = [&](uint16_t mm) {
        return (mm != SENSOR_ERROR_DISTANCE) && (mm <= MATRIX_SENSOR_MAX_DISTANCE_MM);
    };

    auto computePulseInterval = [&](uint16_t distanceMm) {
        if (!isValidDistance(distanceMm)) return 0UL;
        uint16_t constrained = distanceMm < 400 ? 400 : distanceMm;
        long mapped = map(constrained, 400, MATRIX_SENSOR_MAX_DISTANCE_MM, 50, 500);
        unsigned long interval = (unsigned long)mapped;
        interval = (unsigned long)(interval * intervalModifier);
        return interval;
    };

    auto computePulseIntensity = [&](uint16_t distanceMm) {
        if (!isValidDistance(distanceMm)) return (uint8_t)HAPTIC_OFF;
        uint16_t constrained = distanceMm < 200 ? 200 : distanceMm;
        if (constrained > MATRIX_SENSOR_MAX_DISTANCE_MM) {
            constrained = MATRIX_SENSOR_MAX_DISTANCE_MM;
        }
        // DRV2605 RTP uses a signed amplitude domain; keeping values <= 0x7F
        // avoids non-linear/braking behavior seen with higher byte values.
        const uint8_t rtpStrong = 0x7F;
        const uint8_t rtpLight = 0x20;
        long mapped = map(constrained, 200, MATRIX_SENSOR_MAX_DISTANCE_MM, rtpStrong, rtpLight);
        uint8_t intensity = (uint8_t)mapped;
        intensity = (uint8_t)(intensity * intensityModifier);
        if (intensity > 0x7F) intensity = 0x7F;
        if (intensity != 0 && intensity < 0x10) intensity = 0x10;
        return intensity;
    };

    if (currentSituation == FALL_DETECTED) {
        hapticStop(DRIVER_8X8);
        hapticStop(DRIVER_RIGHT_ULTRASONIC);
        hapticStop(DRIVER_LEFT_ULTRASONIC);
        return;
    }

    if (currentSituation == HIGH_STRESS_EVENT) {
        uint8_t stressIntensity = (uint8_t)(HAPTIC_STRONG * intensityModifier);
        uint16_t stressInterval = (uint16_t)(RESPONSE_PULSE_STRESS_MS * intervalModifier);
        unsigned long now = millis();
        if (now - lastHapticPulse >= stressInterval) {
            hapticPulse(DRIVER_8X8, stressIntensity, stressInterval / 2);
            hapticPulse(DRIVER_RIGHT_ULTRASONIC, stressIntensity, stressInterval / 2);
            hapticPulse(DRIVER_LEFT_ULTRASONIC, stressIntensity, stressInterval / 2);
            lastHapticPulse = now;
        }
        return;
    }

    const uint16_t headMm = currentSensors.matrixSensorHeadDetected ? currentSensors.matrixSensorHeadDistance : SENSOR_ERROR_DISTANCE;
    const uint16_t frontMm = currentSensors.matrixSensorWaistDetected ? currentSensors.matrixSensorWaistDistance : SENSOR_ERROR_DISTANCE;
    const uint16_t leftMm = currentSensors.ultrasonicDistances[0];
    const uint16_t rightMm = currentSensors.ultrasonicDistances[1];

    uint16_t closestWaist = SENSOR_ERROR_DISTANCE;
    if (isValidDistance(frontMm)) closestWaist = frontMm;
    if (isValidDistance(leftMm) && (closestWaist == SENSOR_ERROR_DISTANCE || leftMm < closestWaist)) {
        closestWaist = leftMm;
    }
    if (isValidDistance(rightMm) && (closestWaist == SENSOR_ERROR_DISTANCE || rightMm < closestWaist)) {
        closestWaist = rightMm;
    }

    ActiveSource activeSource = SOURCE_NONE;
    uint16_t activeDistanceMm = SENSOR_ERROR_DISTANCE;

    if (isValidDistance(headMm)) {
        activeSource = SOURCE_HEAD;
        activeDistanceMm = headMm;
    } else if (closestWaist != SENSOR_ERROR_DISTANCE) {
        if (isValidDistance(frontMm) && frontMm == closestWaist) {
            activeSource = SOURCE_FRONT;
            activeDistanceMm = frontMm;
        } else if (isValidDistance(leftMm) && (!isValidDistance(rightMm) || leftMm <= rightMm)) {
            activeSource = SOURCE_LEFT;
            activeDistanceMm = leftMm;
        } else if (isValidDistance(rightMm)) {
            activeSource = SOURCE_RIGHT;
            activeDistanceMm = rightMm;
        }
    }

    // Ensure non-selected channels are off before applying current source pulse.
    auto stopAll = [&]() {
        hapticStop(DRIVER_8X8);
        hapticStop(DRIVER_LEFT_ULTRASONIC);
        hapticStop(DRIVER_RIGHT_ULTRASONIC);
    };

    if (activeSource == SOURCE_NONE) {
        stopAll();
        return;
    }

    unsigned long interval = computePulseInterval(activeDistanceMm);
    uint8_t intensity = computePulseIntensity(activeDistanceMm);
    if (interval == 0 || intensity == HAPTIC_OFF) {
        stopAll();
        return;
    }

    static unsigned long lastPriorityToggle = 0;
    static bool priorityOnPhase = false;
    unsigned long now = millis();

    if (now - lastPriorityToggle < interval) {
        return;
    }

    lastPriorityToggle = now;
    priorityOnPhase = !priorityOnPhase;

    if (!priorityOnPhase) {
        stopAll();
        return;
    }

    stopAll();
    if (activeSource == SOURCE_HEAD) {
        hapticPulse(DRIVER_8X8, intensity, (uint16_t)(interval / 2));
    } else if (activeSource == SOURCE_FRONT) {
        hapticPulse(DRIVER_LEFT_ULTRASONIC, intensity, (uint16_t)(interval / 2));
        hapticPulse(DRIVER_RIGHT_ULTRASONIC, intensity, (uint16_t)(interval / 2));
    } else if (activeSource == SOURCE_LEFT) {
        hapticPulse(DRIVER_LEFT_ULTRASONIC, intensity, (uint16_t)(interval / 2));
    } else if (activeSource == SOURCE_RIGHT) {
        hapticPulse(DRIVER_RIGHT_ULTRASONIC, intensity, (uint16_t)(interval / 2));
    }
}

void hapticPulse(uint8_t driverIndex, uint8_t intensity, uint16_t durationMs) {
    // Send haptic pulse via DRV2605L RTP mode
    // Intensity: 0-255 (0 = off, 255 = maximum)

    if (driverIndex >= 3 || intensity == 0) {
        hapticStop(driverIndex);
        return;
    }

    if (intensity > 0x7F) {
        intensity = 0x7F;
    }

    HapticDriverState &driver = hapticDrivers[driverIndex];
    if (!driver.initialized) return;

    // Select correct mux channel
    if (driverIndex == DRIVER_8X8) {
        selectHaptic8x8();
    } else if (driverIndex == DRIVER_RIGHT_ULTRASONIC) {
        selectHapticRightUltrasonic();
    } else if (driverIndex == DRIVER_LEFT_ULTRASONIC) {
        selectHapticLeftUltrasonic();
    }

    // Write to DRV2605L RTP data register
    Wire.beginTransmission(DRV2605_ADDR);
    Wire.write(0x02);           // RTP input register
    Wire.write(intensity);      // RTP data (0-255)
    Wire.endTransmission();

    driver.active = true;
    driver.currentIntensity = intensity;

    if (DEBUG_MODE && intensity > 0) {
        Serial.print("Haptic driver ");
        Serial.print(driverIndex);
        Serial.print(" pulse: ");
        Serial.print(intensity);
        Serial.print(" intensity, ");
        Serial.print(durationMs);
        Serial.println("ms");
    }
}

void hapticStop(uint8_t driverIndex) {
    if (driverIndex >= 3) return;

    HapticDriverState &driver = hapticDrivers[driverIndex];
    if (!driver.active || !driver.initialized) return;

    // Select correct mux channel
    if (driverIndex == DRIVER_8X8) {
        selectHaptic8x8();
    } else if (driverIndex == DRIVER_RIGHT_ULTRASONIC) {
        selectHapticRightUltrasonic();
    } else if (driverIndex == DRIVER_LEFT_ULTRASONIC) {
        selectHapticLeftUltrasonic();
    }

    // Stop haptic vibration
    Wire.beginTransmission(DRV2605_ADDR);
    Wire.write(0x02);  // RTP input register
    Wire.write(0x00);  // Stop vibration
    Wire.endTransmission();

    driver.active = false;
    driver.currentIntensity = 0;
}

uint8_t hapticDriverStatusBits() {
    uint8_t bits = 0;
    if (hapticDrivers[DRIVER_8X8].initialized) {
        bits |= 0x10;
    }
    if (hapticDrivers[DRIVER_RIGHT_ULTRASONIC].initialized) {
        bits |= 0x20;
    }
    if (hapticDrivers[DRIVER_LEFT_ULTRASONIC].initialized) {
        bits |= 0x40;
    }
    return bits;
}