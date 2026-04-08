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
    selectHaptic();  // Route I2C to haptic driver via mux

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
    // Distance-based haptic scaling for obstacle and stress responses
    // EXCLUSION: FALL_DETECTED - no haptic feedback during fall (not useful for safety)
    // In LOW_POWER mode: reduce intensity by 40% and increase intervals for less frequent feedback
    // Closer object = higher intensity + faster pulses

    float intensityModifier = (currentMode == LOW_POWER) ? 0.6f : 1.0f;  // 40% reduction in LOW_POWER
    unsigned long intervalModifier = (currentMode == LOW_POWER) ? 1.5f : 1.0f;  // 50% more time between pulses

    if (currentSituation == OBJECT_FAR) {
        // Far obstacle: light, slow pulses
        hapticIntensity = (uint8_t)(HAPTIC_LIGHT * intensityModifier);
        hapticPulseInterval = (uint16_t)(RESPONSE_PULSE_FAR_MS * intervalModifier);
    } else if (currentSituation == OBJECT_NEAR) {
        // Near obstacle: medium, moderate pulses
        hapticIntensity = (uint8_t)(HAPTIC_MEDIUM * intensityModifier);
        hapticPulseInterval = (uint16_t)(RESPONSE_PULSE_NEAR_MS * intervalModifier);
    } else if (currentSituation == OBJECT_IMMINENT) {
        // Imminent collision: heavy, fast pulses (still strong even in LOW_POWER for safety)
        hapticIntensity = (uint8_t)(HAPTIC_STRONG * 0.85f);  // Slightly reduced but still urgent
        hapticPulseInterval = (uint16_t)(RESPONSE_PULSE_IMMINENT_MS * 1.2f);  // Slightly slower
    } else if (currentSituation == HIGH_STRESS) {
        // High stress: maximum intensity, very fast (reduce if LOW_POWER)
        hapticIntensity = (uint8_t)(HAPTIC_STRONG * intensityModifier);
        hapticPulseInterval = (uint16_t)(RESPONSE_PULSE_STRESS_MS * intervalModifier);
    } else if (currentSituation == FALL_DETECTED) {
        // FALL: NO HAPTIC FEEDBACK - person is falling, haptics not useful for safety
        // Fall response uses LED + buzzer only (handled in responses.cpp handleFallResponse)
        hapticIntensity = HAPTIC_OFF;
        hapticPulseInterval = 0;
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

    selectHaptic();  // Ensure correct I2C mux channel

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

    selectHaptic();  // Ensure correct I2C mux channel

    // Stop haptic vibration
    Wire.beginTransmission(DRV2605_ADDR);
    Wire.write(0x02);  // RTP input register
    Wire.write(0x00);  // Stop vibration
    Wire.endTransmission();

    hapticActive = false;
    hapticCurrentIntensity = 0;
}