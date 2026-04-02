#include "sensors.h"
#include "../imu/imu.h"
#include <Arduino.h>

// ---- FALL STATE ----
bool fallDetected = false;

// cooldown to prevent spam
static unsigned long lastFallTime = 0;
static const unsigned long FALL_COOLDOWN = 5000; // 5 sec

// assuming you already have heart BPM variable
extern int heartBPM;

void initSensors() {
    initIMU();
    initUltrasonic();
    initLight();
    initHeart();
}

void updateSensors() {
    updateUltrasonic();
    updateLight();
    updateHeart();

    bool heartAbnormal = false;

    if (heartBPM > 120 || heartBPM < 50) {
        heartAbnormal = true;
    }

    if (imuFallCandidate &&
        (imuInactive || heartAbnormal) &&
        millis() - lastFallTime > FALL_COOLDOWN) {

        fallDetected = true;
        lastFallTime = millis();

        // reset trigger
        imuFallCandidate = false;
    } else {
        fallDetected = false;
    }
}
}
