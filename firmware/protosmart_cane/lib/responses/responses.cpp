/*
 * Response System - User Feedback
 * Haptic-only alert handling for directional motors and vibration disk
 */

#include "responses.h"
#include <Arduino.h>

// Center vibration disk pulse control
static unsigned long lastDiskToggle = 0;
static bool diskState = false;

// === INDEPENDENT LED CONTROL (detection_logic approach) ===
static unsigned long lastHeadLEDToggle = 0;
static unsigned long lastLeftLEDToggle = 0;
static unsigned long lastRightLEDToggle = 0;
static bool headLEDState = false;
static bool leftLEDState = false;
static bool rightLEDState = false;

static unsigned long isolatedHeadTimer = 0;
static unsigned long isolatedWaistTimer = 0;
static bool isolatedHeadState = false;
static bool isolatedWaistState = false;

static void runBootHapticTest() {
    if (!BOOT_LED_SELF_TEST) {
        return;
    }

#if ISOLATED_SENSOR_TEST_MODE
    const uint8_t hapticPins[] = {
        HAPTIC_TOP_PIN,
        HAPTIC_LEFT_PIN,
        HAPTIC_RIGHT_PIN,
    };
#else
    const uint8_t hapticPins[] = {
        HAPTIC_TOP_PIN,
        HAPTIC_LEFT_PIN,
        HAPTIC_RIGHT_PIN,
    };
#endif

    for (uint8_t index = 0; index < sizeof(hapticPins) / sizeof(hapticPins[0]); index++) {
        digitalWrite(hapticPins[index], HIGH);
        delay(120);
        digitalWrite(hapticPins[index], LOW);
    }
}

static void updateIsolatedTestHaptics() {
    uint16_t frontMm = currentSensors.matrixSensorWaistDetected ? currentSensors.matrixSensorWaistDistance : SENSOR_ERROR_DISTANCE;
    uint16_t leftMm = currentSensors.ultrasonicDistances[0];
    uint16_t rightMm = currentSensors.ultrasonicDistances[1];

    uint16_t closest = frontMm;
    if (leftMm < closest) {
        closest = leftMm;
    }
    if (rightMm < closest) {
        closest = rightMm;
    }

    unsigned long interval = 500;
    if (closest != SENSOR_ERROR_DISTANCE) {
        uint16_t constrainedDistance = max<uint16_t>(closest, 400);
        interval = map(constrainedDistance, 400, MATRIX_SENSOR_MAX_DISTANCE_MM, 50, 500);
    }

    unsigned long now = millis();

    if (currentSensors.matrixSensorHeadDetected) {
        if (now - isolatedHeadTimer >= interval) {
            isolatedHeadTimer = now;
            isolatedHeadState = !isolatedHeadState;
            digitalWrite(HAPTIC_TOP_PIN, isolatedHeadState);
        }
    } else {
        digitalWrite(HAPTIC_TOP_PIN, LOW);
        isolatedHeadState = false;
    }

    if (closest != SENSOR_ERROR_DISTANCE) {
        if (now - isolatedWaistTimer >= interval) {
            isolatedWaistTimer = now;
            isolatedWaistState = !isolatedWaistState;

            digitalWrite(HAPTIC_LEFT_PIN, LOW);
            digitalWrite(HAPTIC_RIGHT_PIN, LOW);

            if (closest == frontMm) {
                digitalWrite(HAPTIC_LEFT_PIN, isolatedWaistState);
                digitalWrite(HAPTIC_RIGHT_PIN, isolatedWaistState);
            } else if (closest == leftMm) {
                digitalWrite(HAPTIC_LEFT_PIN, isolatedWaistState);
            } else if (closest == rightMm) {
                digitalWrite(HAPTIC_RIGHT_PIN, isolatedWaistState);
            }
        }
    } else {
        digitalWrite(HAPTIC_LEFT_PIN, LOW);
        digitalWrite(HAPTIC_RIGHT_PIN, LOW);
        isolatedWaistState = false;
    }
}

void responsesInit() {
    pinMode(HAPTIC_DISK_PIN, OUTPUT);
#if ISOLATED_SENSOR_TEST_MODE
    pinMode(HAPTIC_TOP_PIN, OUTPUT);
    pinMode(HAPTIC_LEFT_PIN, OUTPUT);
    pinMode(HAPTIC_RIGHT_PIN, OUTPUT);
#else
    pinMode(HAPTIC_TOP_PIN, OUTPUT);
    pinMode(HAPTIC_LEFT_PIN, OUTPUT);
    pinMode(HAPTIC_RIGHT_PIN, OUTPUT);
#endif

    // Ensure actuators start in off state
    digitalWrite(HAPTIC_DISK_PIN, LOW);
#if ISOLATED_SENSOR_TEST_MODE
    digitalWrite(HAPTIC_TOP_PIN, LOW);
    digitalWrite(HAPTIC_LEFT_PIN, LOW);
    digitalWrite(HAPTIC_RIGHT_PIN, LOW);
#else
    digitalWrite(HAPTIC_TOP_PIN, LOW);
    digitalWrite(HAPTIC_LEFT_PIN, LOW);
    digitalWrite(HAPTIC_RIGHT_PIN, LOW);
#endif

    runBootHapticTest();

    // Initialize haptic drivers (DRV2605L on mux channels)
    hapticDriverInit();

    if (DEBUG_MODE) {
        Serial.println("responsesInit complete");
    }
}

void vibrationDiskPulse(unsigned long intervalMs) {
    // Pulse center vibration disk at specified interval.
    if (millis() - lastDiskToggle > intervalMs) {
        diskState = !diskState;
        digitalWrite(HAPTIC_DISK_PIN, diskState);
        lastDiskToggle = millis();
    }
}

void vibrationDiskOff() {
    digitalWrite(HAPTIC_DISK_PIN, LOW);
    diskState = false;
}

static unsigned long lastLidarFeedbackToggle = 0;
static bool lidarFeedbackState = false;

// === INDEPENDENT ACTUATION FUNCTIONS (detection_logic inspired) ===

static unsigned long getIntervalFromDistance(uint16_t distanceMm) {
    if (distanceMm >= SENSOR_ERROR_DISTANCE || distanceMm >= MATRIX_SENSOR_MAX_DISTANCE_MM) {
        return 0; // No blinking
    }
    
    // Constrain to valid range and map to interval (50-500ms like detection_logic)
    uint16_t constrainedDist = constrain(distanceMm, OBSTACLE_IMMINENT_MM, MATRIX_SENSOR_MAX_DISTANCE_MM);
    return map(constrainedDist, OBSTACLE_IMMINENT_MM, MATRIX_SENSOR_MAX_DISTANCE_MM, 50, 500);
}

static void updateHeadLED() {
    unsigned long interval = 0;
    
    if (currentSensors.matrixSensorHeadDetected && currentSensors.matrixSensorHeadDistance != SENSOR_ERROR_DISTANCE) {
        interval = getIntervalFromDistance(currentSensors.matrixSensorHeadDistance);
    }
    
    if (interval == 0) {
        digitalWrite(HAPTIC_TOP_PIN, LOW);
        headLEDState = false;
        return;
    }
    
    unsigned long now = millis();
    if (now - lastHeadLEDToggle >= interval) {
        lastHeadLEDToggle = now;
        headLEDState = !headLEDState;
        digitalWrite(HAPTIC_TOP_PIN, headLEDState);
    }
}

static void updateWaistLEDs() {
    // Find closest obstacle for waist zone (front/waist + ultrasonic left/right)
    uint16_t closestDistance = SENSOR_ERROR_DISTANCE;
    bool frontDetected = false;
    bool leftDetected = false;
    bool rightDetected = false;
    
    // Check matrix sensor waist zone
    if (currentSensors.matrixSensorWaistDetected && currentSensors.matrixSensorWaistDistance != SENSOR_ERROR_DISTANCE) {
        closestDistance = currentSensors.matrixSensorWaistDistance;
        frontDetected = true;
    }
    
    // Check ultrasonic sensors
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        if (currentSensors.ultrasonicDistances[i] != SENSOR_ERROR_DISTANCE) {
            if (currentSensors.ultrasonicDistances[i] < closestDistance) {
                closestDistance = currentSensors.ultrasonicDistances[i];
            }
            if (i == 0) leftDetected = true;  // Left ultrasonic
            else rightDetected = true;        // Right ultrasonic
        }
    }
    
    unsigned long interval = getIntervalFromDistance(closestDistance);
    
    if (interval == 0) {
        // No obstacles - turn off all directional haptics
        digitalWrite(HAPTIC_LEFT_PIN, LOW);
        digitalWrite(HAPTIC_RIGHT_PIN, LOW);
        leftLEDState = false;
        rightLEDState = false;
        return;
    }
    
    unsigned long now = millis();
    if (now - lastLeftLEDToggle >= interval) {
        lastLeftLEDToggle = now;
        lastRightLEDToggle = now;  // Sync both LEDs
        
        leftLEDState = !leftLEDState;
        rightLEDState = !rightLEDState;
        
        // Priority system: closest obstacle determines which LED(s) blink
        if (closestDistance == currentSensors.matrixSensorWaistDistance && frontDetected) {
            // Front obstacle - both side haptics
            digitalWrite(HAPTIC_LEFT_PIN, leftLEDState);
            digitalWrite(HAPTIC_RIGHT_PIN, rightLEDState);
        } else if (leftDetected && (!rightDetected || currentSensors.ultrasonicDistances[0] <= currentSensors.ultrasonicDistances[1])) {
            // Left is closest or only left detected
            digitalWrite(HAPTIC_LEFT_PIN, leftLEDState);
            digitalWrite(HAPTIC_RIGHT_PIN, LOW);
        } else if (rightDetected) {
            // Right is closest or only right detected
            digitalWrite(HAPTIC_LEFT_PIN, LOW);
            digitalWrite(HAPTIC_RIGHT_PIN, rightLEDState);
        }
    }
}

void handleResponses() {
#if ISOLATED_SENSOR_TEST_MODE
    vibrationDiskOff();
    updateHapticFeedback();
    return;
#endif

    // OPTIMIZED Response handler for 8-hour continuous operation
    // Strategy: Independent spatial feedback + haptic for all events, buzzer ONLY for imminent collision
    // Power savings: Multi-modal feedback with spatial awareness
    
    // === Update autonomous systems ===
    updateHeadLED();            // Independent head zone feedback
    updateWaistLEDs();          // Independent waist/front + ultrasonic feedback
    updateHapticFeedback();     // Distance-based haptic feedback (primary alert mechanism)

    // Determine overall obstacle response based on per-sensor zones
    bool anyImminent = false;
    bool anyNear = false;
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        if (currentSensors.ultrasonicZones[i] == OBSTACLE_IMMINENT) anyImminent = true;
        if (currentSensors.ultrasonicZones[i] == OBSTACLE_NEAR) anyNear = true;
    }
    if (currentSensors.matrixSensorZone == OBSTACLE_IMMINENT) anyImminent = true;
    if (currentSensors.matrixSensorZone == OBSTACLE_NEAR) anyNear = true;

    // Center vibration disk response - ONLY for imminent threats (<200mm)
    if (anyImminent) {
        vibrationDiskPulse(RESPONSE_PULSE_IMMINENT_MS);
    } else {
        vibrationDiskOff();
    }

    // Special cases for fall and high stress (handled separately from obstacle zones)
    if (currentSituation == FALL_DETECTED) {
        handleFallResponse();
    } else if (currentSituation == HIGH_STRESS_EVENT) {
        // High stress: haptic feedback + no disk vibration pulse override
        vibrationDiskOff();
        emergencyActive = true;
        emergencyStartTime = millis();
    } else {
        emergencyActive = false;
    }
}

void handleFallResponse() {
    // FALL RESPONSE - haptic-only (directional motors + center vibration disk)
    // Pattern:
    //   Phase 1 (0-3s): strong, rapid pulses
    //   Phase 2 (3-30s): medium, slower pulses
    //   Timeout: stop pulses and return to standard logic

    if (!emergencyActive) {
        emergencyActive = true;
        emergencyStartTime = millis();
        if (DEBUG_MODE) Serial.println("FALL DETECTED - haptic alert activated");
    }

    unsigned long timeSinceFall = millis() - emergencyStartTime;

    if (timeSinceFall < EMERGENCY_INITIAL_INTENSITY_MS) {
        // Phase 1: rapid strong haptic pulses
        vibrationDiskPulse(RESPONSE_PULSE_IMMINENT_MS);
        hapticPulse(DRIVER_8X8, HAPTIC_STRONG, RESPONSE_PULSE_IMMINENT_MS / 2);
        hapticPulse(DRIVER_LEFT_ULTRASONIC, HAPTIC_STRONG, RESPONSE_PULSE_IMMINENT_MS / 2);
        hapticPulse(DRIVER_RIGHT_ULTRASONIC, HAPTIC_STRONG, RESPONSE_PULSE_IMMINENT_MS / 2);
    } else if (timeSinceFall < EMERGENCY_DURATION_MS) {
        // Phase 2: sustained medium haptic pulses
        vibrationDiskPulse(RESPONSE_PULSE_NEAR_MS);
        hapticPulse(DRIVER_8X8, HAPTIC_MEDIUM, RESPONSE_PULSE_NEAR_MS / 2);
        hapticPulse(DRIVER_LEFT_ULTRASONIC, HAPTIC_MEDIUM, RESPONSE_PULSE_NEAR_MS / 2);
        hapticPulse(DRIVER_RIGHT_ULTRASONIC, HAPTIC_MEDIUM, RESPONSE_PULSE_NEAR_MS / 2);
    } else {
        // Timeout reached - return to normal haptic control but keep emergency flag
        vibrationDiskOff();
        hapticStop(DRIVER_8X8);
        hapticStop(DRIVER_LEFT_ULTRASONIC);
        hapticStop(DRIVER_RIGHT_ULTRASONIC);
        emergencyActive = false;
        if (DEBUG_MODE) Serial.println("Fall alert timeout - continuing with standard haptic control");
    }
}