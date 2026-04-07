/*
 * Haptic Driver Implementation (DRV2605L)
 * Translates distance-based feedback to haptic patterns
 */

#include "haptic_driver.h"
#include <Wire.h>

uint8_t hapticIntensity = 0;
bool hapticActive = false;

static unsigned long lastHapticPulse = 0;
static uint16_t hapticPulseInterval = 0;
static uint8_t hapticCurrentIntensity = 0;

void hapticDriverInit() {
    selectIMU();  // Route I2C to haptic driver via mux

    Wire.beginTransmission(DRV2605_ADDR);
    if (Wire.endTransmission() == 0) {
        // Initialize DRV2605L
        // Set to RTP (real-time playback) mode for direct control
        Wire.beginTransmission(DRV2605_ADDR);
        Wire.write(0x01);  // Mode register
        Wire.write(0x05);  // RTP mode
        Wire.endTransmission();

        if (DEBUG_MODE) Serial.println("Haptic driver initialized (DRV2605L)");
    } else {
        if (DEBUG_MODE) Serial.println("Haptic driver not found");
    }
}

void updateHapticFeedback() {
    // Distance-based haptic scaling similar to LED feedback
    // Closer object = higher intensity + faster pulses

    if (currentSituation == OBJECT_FAR) {
        // Far obstacle: light, slow pulses
        hapticIntensity = HAPTIC_LIGHT;
        hapticPulseInterval = RESPONSE_PULSE_FAR_MS;
    } else if (currentSituation == OBJECT_NEAR) {
        // Near obstacle: medium, moderate pulses
        hapticIntensity = HAPTIC_MEDIUM;
        hapticPulseInterval = RESPONSE_PULSE_NEAR_MS;
    } else if (currentSituation == OBJECT_IMMINENT) {
        // Imminent collision: heavy, fast pulses
        hapticIntensity = HAPTIC_STRONG;
        hapticPulseInterval = RESPONSE_PULSE_IMMINENT_MS;
    } else if (currentSituation == HIGH_STRESS) {
        // High stress: maximum intensity, very fast
        hapticIntensity = HAPTIC_STRONG;
        hapticPulseInterval = RESPONSE_PULSE_STRESS_MS;
    } else if (currentSituation == FALL_DETECTED) {
        // Fall: intense sharp pulses
        hapticIntensity = HAPTIC_STRONG;
        hapticPulseInterval = RESPONSE_PULSE_FALL_MS;
    } else {
        // No obstacle: no haptic feedback
        hapticIntensity = HAPTIC_OFF;
        hapticPulseInterval = 0;
    }

    // Send haptic pulses based on interval
    if (hapticPulseInterval > 0) {
        unsigned long now = millis();
        if (now - lastHapticPulse > hapticPulseInterval) {
            hapticPulse(hapticIntensity, hapticPulseInterval / 2);
            lastHapticPulse = now;
        }
    } else {
        hapticStop();
    }
}

void hapticPulse(uint8_t intensity, uint16_t durationMs) {
    // Send haptic pulse via DRV2605L RTP mode
    // Intensity: 0-255 (0 = off, 255 = maximum)

    if (intensity == 0) {
        hapticStop();
        return;
    }

    selectIMU();  // Ensure correct I2C mux channel

    // Write to DRV2605L RTP data register
    Wire.beginTransmission(DRV2605_ADDR);
    Wire.write(0x02);           // RTP input register
    Wire.write(intensity);      // RTP data (0-255)
    Wire.endTransmission();

    hapticActive = true;
    hapticCurrentIntensity = intensity;

    if (DEBUG_MODE && intensity > 0) {
        Serial.print("Haptic pulse: ");
        Serial.print(intensity);
        Serial.print(" intensity, ");
        Serial.print(durationMs);
        Serial.println("ms");
    }
}

void hapticStop() {
    if (!hapticActive) return;

    selectIMU();  // Ensure correct I2C mux channel

    // Stop haptic vibration
    Wire.beginTransmission(DRV2605_ADDR);
    Wire.write(0x02);  // RTP input register
    Wire.write(0x00);  // Stop vibration
    Wire.endTransmission();

    hapticActive = false;
    hapticCurrentIntensity = 0;
}