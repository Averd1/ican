/*
 * Response System - User Feedback
 * Manages buzzer, LED alerts, and haptic feedback based on detected situations
 */

#include "responses.h"
#include <Arduino.h>

// Buzzer control variables
static unsigned long lastBuzzerToggle = 0;
static bool buzzerState = false;

// === INDEPENDENT LED CONTROL (detection_logic approach) ===
static unsigned long lastHeadLEDToggle = 0;
static unsigned long lastLeftLEDToggle = 0;
static unsigned long lastRightLEDToggle = 0;
static bool headLEDState = false;
static bool leftLEDState = false;
static bool rightLEDState = false;

static unsigned long lastFrontHapticLEDToggle = 0;
static unsigned long lastLeftHapticLEDToggle = 0;
static unsigned long lastRightHapticLEDToggle = 0;
static bool frontHapticLEDState = false;
static bool leftHapticLEDState = false;
static bool rightHapticLEDState = false;

void responsesInit() {
    pinMode(BUZZER_PIN, OUTPUT);
    if (LED_PIN >= 0) {
        pinMode(LED_PIN, OUTPUT);
    }
    pinMode(LED_HEAD_PIN, OUTPUT);
    pinMode(LED_LEFT_PIN, OUTPUT);
    pinMode(LED_RIGHT_PIN, OUTPUT);
    pinMode(LED_HAPTIC_FRONT_PIN, OUTPUT);
    pinMode(LED_HAPTIC_LEFT_PIN, OUTPUT);
    pinMode(LED_HAPTIC_RIGHT_PIN, OUTPUT);

    // Ensure actuators start in off state
    digitalWrite(BUZZER_PIN, LOW);
    if (LED_PIN >= 0) {
        analogWrite(LED_PIN, LED_OFF);
    }
    digitalWrite(LED_HEAD_PIN, LOW);
    digitalWrite(LED_LEFT_PIN, LOW);
    digitalWrite(LED_RIGHT_PIN, LOW);
    digitalWrite(LED_HAPTIC_FRONT_PIN, LOW);
    digitalWrite(LED_HAPTIC_LEFT_PIN, LOW);
    digitalWrite(LED_HAPTIC_RIGHT_PIN, LOW);

    // Initialize LED driver for illumination
    ledDriverInit();

    // Initialize haptic driver
    hapticDriverInit();
}

void setLED(int brightness) {
    analogWrite(LED_ILLUMINATION_PIN, brightness);
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
        digitalWrite(LED_HEAD_PIN, LOW);
        headLEDState = false;
        return;
    }
    
    unsigned long now = millis();
    if (now - lastHeadLEDToggle >= interval) {
        lastHeadLEDToggle = now;
        headLEDState = !headLEDState;
        digitalWrite(LED_HEAD_PIN, headLEDState);
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
        // No obstacles - turn off all waist LEDs
        digitalWrite(LED_LEFT_PIN, LOW);
        digitalWrite(LED_RIGHT_PIN, LOW);
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
            // Front obstacle - both LEDs
            digitalWrite(LED_LEFT_PIN, leftLEDState);
            digitalWrite(LED_RIGHT_PIN, rightLEDState);
        } else if (leftDetected && (!rightDetected || currentSensors.ultrasonicDistances[0] <= currentSensors.ultrasonicDistances[1])) {
            // Left is closest or only left detected
            digitalWrite(LED_LEFT_PIN, leftLEDState);
            digitalWrite(LED_RIGHT_PIN, LOW);
        } else if (rightDetected) {
            // Right is closest or only right detected
            digitalWrite(LED_LEFT_PIN, LOW);
            digitalWrite(LED_RIGHT_PIN, rightLEDState);
        }
    }
}

// === HAPTIC-LIKE LED FEEDBACK (mirrors haptic driver logic) ===
static unsigned long lastHapticLEDUpdate = 0;

static void updateHapticMimicLED(uint16_t distanceMm, uint8_t pin, unsigned long &lastToggle, bool &state) {
    if (distanceMm == SENSOR_ERROR_DISTANCE || distanceMm >= MATRIX_SENSOR_MAX_DISTANCE_MM || distanceMm == 0) {
        digitalWrite(pin, LOW);
        state = false;
        return;
    }

    unsigned long interval = getIntervalFromDistance(distanceMm);
    if (interval == 0) {
        digitalWrite(pin, LOW);
        state = false;
        return;
    }

    unsigned long now = millis();
    if (now - lastToggle >= interval) {
        lastToggle = now;
        state = !state;
        digitalWrite(pin, state);
    }
}

static void updateHapticLikeLEDs() {
    if (currentSituation == FALL_DETECTED) {
        digitalWrite(LED_HAPTIC_FRONT_PIN, LOW);
        digitalWrite(LED_HAPTIC_LEFT_PIN, LOW);
        digitalWrite(LED_HAPTIC_RIGHT_PIN, LOW);
        frontHapticLEDState = false;
        leftHapticLEDState = false;
        rightHapticLEDState = false;
        return;
    }

    // 8x8 front matrix sensor drives the front haptic mimic LED
    if (currentSensors.matrixSensorWaistDetected && currentSensors.matrixSensorWaistDistance != SENSOR_ERROR_DISTANCE) {
        updateHapticMimicLED(currentSensors.matrixSensorWaistDistance, LED_HAPTIC_FRONT_PIN,
                            lastFrontHapticLEDToggle, frontHapticLEDState);
    } else {
        digitalWrite(LED_HAPTIC_FRONT_PIN, LOW);
        frontHapticLEDState = false;
    }

    // Left ultrasonic sensor drives the left haptic mimic LED
    if (currentSensors.ultrasonicZones[0] != OBSTACLE_NONE && currentSensors.ultrasonicDistances[0] != SENSOR_ERROR_DISTANCE) {
        updateHapticMimicLED(currentSensors.ultrasonicDistances[0], LED_HAPTIC_LEFT_PIN,
                            lastLeftHapticLEDToggle, leftHapticLEDState);
    } else {
        digitalWrite(LED_HAPTIC_LEFT_PIN, LOW);
        leftHapticLEDState = false;
    }

    // Right ultrasonic sensor drives the right haptic mimic LED
    if (currentSensors.ultrasonicZones[1] != OBSTACLE_NONE && currentSensors.ultrasonicDistances[1] != SENSOR_ERROR_DISTANCE) {
        updateHapticMimicLED(currentSensors.ultrasonicDistances[1], LED_HAPTIC_RIGHT_PIN,
                            lastRightHapticLEDToggle, rightHapticLEDState);
    } else {
        digitalWrite(LED_HAPTIC_RIGHT_PIN, LOW);
        rightHapticLEDState = false;
    }
}

void handleResponses() {
    // OPTIMIZED Response handler for 8-hour continuous operation
    // Strategy: Independent spatial feedback + haptic for all events, buzzer ONLY for imminent collision
    // Power savings: Multi-modal feedback with spatial awareness
    
    // === Update autonomous systems ===
    updateLEDIllumination();    // Auto-control LED based on light sensor (only when <100 lux)
    updateHeadLED();            // Independent head zone feedback
    updateWaistLEDs();          // Independent waist/front + ultrasonic feedback
    updateHapticLikeLEDs();     // LED feedback mirroring haptic driver logic
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

    // Buzzer response - ONLY for imminent threats (<200mm)
    if (anyImminent) {
        buzzerPulse(RESPONSE_PULSE_IMMINENT_MS);  // Fast buzzer pulse for imminent
    } else {
        buzzerOff();
    }

    // Special cases for fall and high stress (handled separately from obstacle zones)
    if (currentSituation == FALL_DETECTED) {
        handleFallResponse();  // Haptic pulsed response only
    } else if (currentSituation == HIGH_STRESS_EVENT) {
        // High stress: haptic feedback (no LED/buzzer)
        buzzerOff();
        emergencyActive = true;
        emergencyStartTime = millis();
    } else {
        emergencyActive = false;
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