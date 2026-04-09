#include "pulse.h"
#include <PulseSensorPlayground.h>

// Create PulseSensorPlayground object - requires PulseSensorPlayground library
PulseSensorPlayground pulseSensor;

int heartBPM = 0;
int heartRaw = 0;
bool pulseDetected = false;
bool heartAbnormal = false;

void initPulse() {
    // Configure the PulseSensor with proper pin assignments
    pulseSensor.analogInput(PULSE_PIN);
    pulseSensor.blinkOnPulse(PULSE_LED);
    pulseSensor.setThreshold(PULSE_THRESHOLD);

    if (pulseSensor.begin()) {
        Serial.println("PulseSensor initialized successfully!");
    } else {
        Serial.println("PulseSensor initialization failed!");
    }
}

void updatePulseData() {
    // Read the latest sample from the PulseSensor
    heartRaw = pulseSensor.getLatestSample();

    // Check for beat detection
    if (pulseSensor.sawStartOfBeat()) {
        heartBPM = pulseSensor.getBeatsPerMinute();
        pulseDetected = true;

        // Check for abnormal heart rate (emergency condition)
        heartAbnormal = (heartBPM > 120 || heartBPM < 50);

        // Optional debug output
        // Serial.print("BPM: ");
        // Serial.println(heartBPM);
    } else {
        pulseDetected = false;
    }
}