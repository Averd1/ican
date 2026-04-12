/*
 * Sleep Manager Implementation
 */

#include "sleep_manager.h"
#include "../mode/mode.h"
#include <Arduino.h>

SleepState sleepState = {SLEEP_NONE, 0, 0, false, {}, 0};

void sleepManagerInit() {
    sleepState.lastMotionTime = millis();
    sleepState.lastTouchTime = millis();
    sleepState.currentSleepMode = SLEEP_NONE;
    if (DEBUG_MODE) Serial.println("Sleep manager initialized");
}

void updateSleepManager() {
    unsigned long now = millis();

    // Update motion tracking from IMU
    float accelMag = sqrt(
        currentSensors.imu.ax * currentSensors.imu.ax +
        currentSensors.imu.ay * currentSensors.imu.ay +
        currentSensors.imu.az * currentSensors.imu.az
    );

    if (accelMag > MOTION_THRESHOLD_WAKE) {
        sleepState.lastMotionTime = now;
        if (sleepState.currentSleepMode != SLEEP_NONE) {
            wakeFromSleep();
        }
    }

    // Record state periodically for history
    static unsigned long lastHistoryUpdate = 0;
    if (now - lastHistoryUpdate > 5000) {  // Every 5 seconds
        recordStateHistory();
        lastHistoryUpdate = now;
    }

    // Check if user has been inactive for extended periods
    unsigned long inactivityTime = now - sleepState.lastMotionTime;

    // Transition to CAUTIOUS_SLEEP
    if (inactivityTime > INACTIVITY_TIMEOUT_CAUTIOUS &&
        sleepState.currentSleepMode == SLEEP_NONE &&
        isSafeToSleep()) {

        setMode(LOW_POWER);  // Already reduced sampling
        enterCautiousSleep();

        if (DEBUG_MODE) {
            Serial.println("ENTERING CAUTIOUS_SLEEP - User inactive 5 min, normal vitals");
        }
    }

    // Transition to DEEP_SLEEP
    if (inactivityTime > INACTIVITY_TIMEOUT_DEEP &&
        sleepState.currentSleepMode == SLEEP_CAUTIOUS &&
        isSafeToSleep()) {

        enterDeepSleep();

        if (DEBUG_MODE) {
            Serial.println("ENTERING DEEP_SLEEP - User inactive 20 min, system stable");
        }
    }
}

void recordStateHistory() {
    // Record current state in circular buffer
    StateHistory& entry = sleepState.history[sleepState.historyIndex];

    entry.flags = 0;
    if (currentSituation == FALL_DETECTED) entry.flags |= 0x01;
    if (currentSituation == HIGH_STRESS_EVENT) entry.flags |= 0x02;
    if (emergencyActive) entry.flags |= 0x04;

    entry.heartBPM = currentSensors.heartBPM;
    entry.minDistance = currentSensors.matrixSensorDistance; // Use primary sensor
    entry.timestamp = millis();

    // Move to next slot
    sleepState.historyIndex = (sleepState.historyIndex + 1) % STATE_HISTORY_SIZE;
}

bool isSafeToSleep() {
    // Check recent history for emergencies or abnormal conditions
    for (uint8_t i = 0; i < STATE_HISTORY_SIZE; i++) {
        StateHistory& entry = sleepState.history[i];
        if (entry.flags & 0x01 || entry.flags & 0x02 || entry.flags & 0x04) {
            // Emergency or high stress detected in history
            return false;
        }

        // Check for abnormal heart rate
        if (entry.heartBPM > HEART_ABNORMAL_HIGH_BPM || 
            (entry.heartBPM > 0 && entry.heartBPM < HEART_ABNORMAL_LOW_BPM)) {
            return false;
        }
    }

    // All clear - safe to sleep
    return true;
}

void enterCautiousSleep() {
    sleepState.currentSleepMode = SLEEP_CAUTIOUS;

    // In CAUTIOUS_SLEEP:
    // - IMU stays active at minimal rate
    // - LiDAR/Ultrasonic disabled (very unlikely to hit something if stationary)
    // - Pulse sensor off
    // - LEDs off
    // - Ready to wake on motion

    if (DEBUG_MODE) Serial.println("Cautious Sleep: Minimal sensors active, motion-sensitive");
}

void enterDeepSleep() {
    sleepState.currentSleepMode = SLEEP_DEEP;

    // In DEEP_SLEEP:
    // - Only IMU interrupt enabled
    // - All other sensors off
    // - BLE minimal (keep advertisement)
    // - Lowest possible power draw
    // - Wait for user to pick up cane (motion detected)

    if (DEBUG_MODE) Serial.println("Deep Sleep: Cane placed down, ultra-low power mode active");

    // TODO: Configure IMU for interrupt-only mode if hardware supports it
    // TODO: Reduce ESP32 to ULP (ultra-low-power) core if available
}

void wakeFromSleep() {
    if (sleepState.currentSleepMode != SLEEP_NONE) {
        sleepState.currentSleepMode = SLEEP_NONE;
        setMode(NORMAL);

        if (DEBUG_MODE) {
            Serial.println("WAKE FROM SLEEP - Motion detected, returning to normal mode");
        }
    }
}