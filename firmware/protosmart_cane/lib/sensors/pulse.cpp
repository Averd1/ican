/*
 * Pulse Sensor (Heart Rate) Implementation
 * Handles heart rate monitoring for emergency detection
 */

#include "pulse.h"

// PulseSensor library requires this macro to be defined in exactly one sketch/module file.
#define USE_ARDUINO_INTERRUPTS false
#include <PulseSensorPlayground.h>

// PulseSensor instance
static PulseSensorPlayground* pulseSensor = nullptr;

void pulseInit() {
    if (!pulseSensor) pulseSensor = new PulseSensorPlayground();
    // Configure the PulseSensor
    pulseSensor->analogInput(HEART_PIN);
    // INT is not wired in this project; keep pulse sampling in polled mode only.
    // Also disable pulse-linked LED output because all user feedback is haptic-only.
    pulseSensor->setThreshold(HEART_THRESHOLD);

    if (pulseSensor->begin()) {
        if (DEBUG_MODE) Serial.println("Pulse sensor initialized successfully");
        systemFaults.heart_fail = false;
    } else {
        if (DEBUG_MODE) Serial.println("Pulse sensor initialization failed!");
        systemFaults.heart_fail = true;
    }
}

void pulseUpdate() {
    if (!pulseSensor) return;
    // Read the latest sample from the PulseSensor
    currentSensors.heartRaw = pulseSensor->getLatestSample();

    // Check for beat detection
    if (pulseSensor->sawStartOfBeat()) {
        currentSensors.heartBPM = pulseSensor->getBeatsPerMinute();
        currentSensors.pulseDetected = true;

        // Check for abnormal heart rate
        currentSensors.heartAbnormal = (currentSensors.heartBPM > HEART_ABNORMAL_HIGH_BPM ||
                                       currentSensors.heartBPM < HEART_ABNORMAL_LOW_BPM);

        systemFaults.heart_fail = false;
    } else {
        currentSensors.pulseDetected = false;
        // Don't mark as failed immediately - heart rate can be irregular
    }
}