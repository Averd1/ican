#include "imu.h"
#include "../mux/mux.h"
#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>
#include <math.h>

#define IMU_CHANNEL 0

Adafruit_LSM6DSOX lsm6dsox;
IMUData imu;

// ---- FALL DETECTION STATE ----
bool imuFallCandidate = false;
bool imuInactive = false;

static bool freeFallDetected = false;
static unsigned long freeFallStartTime = 0;
static unsigned long lastMotionTime = 0;

// ---- TUNABLE PARAMETERS ----
static const float FREE_FALL_THRESHOLD = 4.0;     // m/s^2 (~0.4g)
static const float IMPACT_THRESHOLD = 25.0;       // m/s^2 (~2.5g)
static const unsigned long IMPACT_WINDOW = 500;  // ms
static const unsigned long INACTIVITY_TIME = 2000; // ms

void initIMU() {
    selectMux(IMU_CHANNEL);

    if (!lsm6dsox.begin_I2C()) {
        Serial.println("IMU NOT FOUND");
        while (1);
    }

    Serial.println("IMU READY");
}

void updateIMU() {
    selectMux(IMU_CHANNEL);

    sensors_event_t accel, gyro, temp;
    lsm6dsox.getEvent(&accel, &gyro, &temp);

    imu.ax = accel.acceleration.x;
    imu.ay = accel.acceleration.y;
    imu.az = accel.acceleration.z;

    imu.gx = gyro.gyro.x;
    imu.gy = gyro.gyro.y;
    imu.gz = gyro.gyro.z;

    // ---- FALL DETECTION LOGIC ----

    float mag = sqrt(
        imu.ax * imu.ax +
        imu.ay * imu.ay +
        imu.az * imu.az
    );

    // Track motion → inactivity detection
    if (mag > 2.0) {  // small motion threshold (~0.2g)
        lastMotionTime = millis();
        imuInactive = false;
    }

    if (millis() - lastMotionTime > INACTIVITY_TIME) {
        imuInactive = true;
    }

    // Detect free fall
    if (mag < FREE_FALL_THRESHOLD) {
        freeFallDetected = true;
        freeFallStartTime = millis();
    }

    // Detect impact after free fall
    if (freeFallDetected && mag > IMPACT_THRESHOLD) {

        freeFallDetected = false;

        if (millis() - freeFallStartTime < IMPACT_WINDOW) {
            imuFallCandidate = true;
        }
    }
}
