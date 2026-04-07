/*
 * Response System - User Feedback
 * Manages buzzer, LED alerts, and haptic feedback based on detected situations
 */

#include "responses.h"
#include <Arduino.h>

// Buzzer control variables
static unsigned long lastBuzzerToggle = 0;
static bool buzzerState = false;

void responsesInit() {
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(LED_PIN, OUTPUT);

    // Ensure actuators start in off state
    digitalWrite(BUZZER_PIN, LOW);
    analogWrite(LED_PIN, LED_OFF);

    // Initialize LED driver for illumination
    ledDriverInit();

    // Initialize haptic driver
    hapticDriverInit();
}

void setLED(int brightness) {
    analogWrite(LED_PIN, brightness);
}

void buzzerPulse(unsigned long intervalMs) {
    // Pulse buzzer at specified interval for different alert patterns
    if (millis() - lastBuzzerToggle > intervalMs) {
        buzzerState = !buzzerState;
        digitalWrite(BUZZER_PIN, buzzerState);
        lastBuzzerToggle = millis();
    }
}

void buzzerOff() {
    digitalWrite(BUZZER_PIN, LOW);
    buzzerState = false;
}

void handleResponses() {
    // OPTIMIZED Response handler for 8-hour continuous operation
    // Strategy: Haptic feedback for all events, LED only for low-light navigation,
    //           Buzzer ONLY for imminent collision (<200mm)
    //
    // Power savings: Removes LED/buzzer from fall, obstacle-far, obstacle-near events
    //                Haptic driver is more efficient than buzzer+LED combination

    // === Update autonomous systems ===
    updateLEDIllumination();    // Auto-control LED based on light sensor (only when <100 lux)
    updateHapticFeedback();     // Distance-based haptic feedback (primary alert mechanism)

    switch(currentSituation) {
        case OBJECT_FAR:
            // Distant obstacle: Haptic feedback only (no LED/buzzer to save power)
            buzzerOff();                    // No buzzer for distant obstacles
            // LED stays as-is from updateLEDIllumination() (low-light only)
            // Haptic driver handles intensity automatically
            emergencyActive = false;
            break;

        case OBJECT_NEAR:
            // Near obstacle: Haptic feedback only (no LED/buzzer)
            buzzerOff();                    // No buzzer
            // LED stays as-is from updateLEDIllumination()
            // Haptic driver handles increased intensity
            emergencyActive = false;
            break;

        case OBJECT_IMMINENT:
            // IMMINENT COLLISION: Haptic + Buzzer pulse only (no LED)
            buzzerPulse(RESPONSE_PULSE_IMMINENT_MS);  // Fast buzzer pulse
            // LED stays as-is from updateLEDIllumination()
            // Haptic driver at maximum intensity for tactile alert
            emergencyActive = false;
            break;

        case FALL_DETECTED:
            // FALL: Haptic vibration pattern only (no LED, no buzzer)
            handleFallResponse();  // Haptic pulsed response only
            break;

        case HIGH_STRESS:
            // High stress: Haptic feedback (no LED/buzzer)
            buzzerOff();
            // Haptic driver handles high-intensity vibration
            emergencyActive = true;
            emergencyStartTime = millis();
            break;

        default:
            // No situation: All alerts off (except LED if low-light)
            buzzerOff();
            // LED stays as-is from updateLEDIllumination()
            emergencyActive = false;
            break;
    }

    // Emergency timeout protection - prevent indefinite alerts
    if (emergencyActive && (millis() - emergencyStartTime > EMERGENCY_DURATION_MS)) {
        emergencyActive = false;
        buzzerOff();
        if (DEBUG_MODE) Serial.println("Emergency timeout - continuing in normal mode");
    }
}

void handleFallResponse() {
    // OPTIMIZED Fall response - haptic vibration only
    // No buzzer or LED (saves 200+ mA, reduces power draw significantly)
    // Single vibration pattern for fall detection
    //
    // Haptic pattern: Strong vibration pulses to alert user
    // Duration: Full emergency timeout (30s max)

    if (!emergencyActive) {
        emergencyActive = true;
        emergencyStartTime = millis();
        if (DEBUG_MODE) Serial.println("FALL DETECTED - Haptic alert activated");
    }

    unsigned long timeSinceFall = millis() - emergencyStartTime;

    if (timeSinceFall < EMERGENCY_INITIAL_INTENSITY_MS) {
        // Phase 1: Strong vibration pattern for immediate attention
        hapticPulse(255, 150);  // Max intensity, 150ms pulses
    } else if (timeSinceFall < EMERGENCY_DURATION_MS) {
        // Phase 2: Continued haptic vibration (help is on way)
        hapticPulse(200, 200);  // High intensity, 200ms pulses
    } else {
        // Timeout reached - stop alerts
        hapticStop();
        emergencyActive = false;
        if (DEBUG_MODE) Serial.println("Fall alert timeout");
    }
}