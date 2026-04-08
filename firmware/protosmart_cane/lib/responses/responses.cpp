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
    // FALL RESPONSE - LED + Buzzer only (NO HAPTICS)
    // Rationale: Person is already falling; haptic feedback provides no safety value.
    //           Focus on maximum visibility (LED) and audio alert (buzzer).
    //
    // Pattern:
    //   Phase 1 (0-3s): LED full bright + rapid buzzer pulses (95% brightness, 50ms buzzer)
    //   Phase 2 (3-30s): LED medium bright + slow buzzer pulses (70% brightness, 150ms buzzer)
    //   Timeout: After 30s, return to normal + keep emergency registered with app
    //
    // User can extend alert via app or manual recovery sequence

    if (!emergencyActive) {
        emergencyActive = true;
        emergencyStartTime = millis();
        if (DEBUG_MODE) Serial.println("FALL DETECTED - LED + Buzzer alert activated (NO HAPTICS)");
    }

    unsigned long timeSinceFall = millis() - emergencyStartTime;

    if (timeSinceFall < EMERGENCY_INITIAL_INTENSITY_MS) {
        // Phase 1: Maximum visibility + rapid audio alert
        setLED(LED_BRIGHT);                         // 255 brightness for immediate visibility
        buzzerPulse(RESPONSE_PULSE_IMMINENT_MS);   // Very fast buzzer pulses (50ms)
    } else if (timeSinceFall < EMERGENCY_DURATION_MS) {
        // Phase 2: Sustained visibility + slower audio feedback
        setLED(LED_MEDIUM);                        // 180 brightness (still prominent)
        buzzerPulse(RESPONSE_PULSE_NEAR_MS);       // Moderate speed pulses (150ms)
    } else {
        // Timeout reached - return to normal LED control but keep emergency flag
        buzzerOff();
        emergencyActive = false;
        if (DEBUG_MODE) Serial.println("Fall alert timeout - continuing with standard LED control");
    }
}