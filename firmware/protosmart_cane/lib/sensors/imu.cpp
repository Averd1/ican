/*
 * IMU Sensor (LSM6DSOX) Implementation
 * Handles fall detection and orientation sensing
 */

#include "imu.h"
#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include <math.h>

// IMU instance
static Adafruit_LSM6DSOX* lsm6dsox = nullptr;

// Fall detection state variables
static bool freeFallDetected = false;
static unsigned long freeFallStartTime = 0;
static unsigned long lastMotionTime = 0;

void imuInit() {
    // IMU is wired to the secondary I2C bus on D6/D7
    if (!lsm6dsox) lsm6dsox = new Adafruit_LSM6DSOX();
    if (!lsm6dsox->begin_I2C(IMU_I2C_ADDR, &Wire1)) {
        if (DEBUG_MODE) Serial.println("IMU initialization failed!");
        systemFaults.imu_fail = true;
        return;
    }

    if (DEBUG_MODE) Serial.println("IMU initialized successfully");
    systemFaults.imu_fail = false;
}

void imuUpdate() {
    sensors_event_t accel, gyro, temp;
    if (!lsm6dsox || !lsm6dsox->getEvent(&accel, &gyro, &temp)) {
        // Sensor read failed
        systemFaults.imu_fail = true;
        return;
    }

    // Update sensor data
    currentSensors.imu.ax = accel.acceleration.x;
    currentSensors.imu.ay = accel.acceleration.y;
    currentSensors.imu.az = accel.acceleration.z;
    currentSensors.imu.gx = gyro.gyro.x;
    currentSensors.imu.gy = gyro.gyro.y;
    currentSensors.imu.gz = gyro.gyro.z;

    // Calculate acceleration magnitude for fall detection
    float accelMag = sqrt(
        currentSensors.imu.ax * currentSensors.imu.ax +
        currentSensors.imu.ay * currentSensors.imu.ay +
        currentSensors.imu.az * currentSensors.imu.az
    );

    // === FALL DETECTION LOGIC ===

    // Detect free fall (very low acceleration)
    if (accelMag < FALL_FREEFALL_THRESHOLD) {
        if (!freeFallDetected) {
            freeFallDetected = true;
            freeFallStartTime = millis();
        }
    } else {
        freeFallDetected = false;
    }

    // Detect impact after free fall within time window
    if (freeFallDetected && accelMag > FALL_IMPACT_THRESHOLD) {
        unsigned long timeSinceFreeFall = millis() - freeFallStartTime;
        if (timeSinceFreeFall < FALL_IMPACT_WINDOW) {
            // Fall detected! This will trigger emergency mode
            freeFallDetected = false;  // Reset for next detection
        }
    }

    // Track motion for inactivity detection
    if (accelMag > 1.0f) {  // Some motion detected
        lastMotionTime = millis();
    }

    // Mark sensor as working
    systemFaults.imu_fail = false;
}