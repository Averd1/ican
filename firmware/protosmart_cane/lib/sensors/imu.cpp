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

enum FallState : uint8_t {
    FALL_STATE_NORMAL = 0,
    FALL_STATE_FREE_FALL,
};

static FallState fallState = FALL_STATE_NORMAL;
static unsigned long freeFallStartTime = 0;
static unsigned long lastFallTime = 0;
static float orientationFilteredSignedZ = 0.0f;

void imuInit() {
    // IMU is wired to the secondary I2C bus on D6/D7
    if (!lsm6dsox) lsm6dsox = new Adafruit_LSM6DSOX();

    bool ok = lsm6dsox->begin_I2C(IMU_I2C_ADDR, &Wire1);
    if (!ok && IMU_I2C_ADDR != 0x6B) {
        ok = lsm6dsox->begin_I2C(0x6B, &Wire1);
    }

    if (!ok) {
        if (DEBUG_MODE) Serial.println("IMU initialization failed!");
        systemFaults.imu_fail = true;
        imuOrientationOk = false;
        return;
    }

    if (DEBUG_MODE) Serial.println("IMU initialized successfully");
    systemFaults.imu_fail = false;
    imuFallDetected = false;
    imuOrientationOk = true;
    fallState = FALL_STATE_NORMAL;
}

void imuUpdate() {
    sensors_event_t accel, gyro, temp;
    if (!lsm6dsox || !lsm6dsox->getEvent(&accel, &gyro, &temp)) {
        // Sensor read failed
        systemFaults.imu_fail = true;
        imuOrientationOk = false;
        return;
    }

    // Update sensor data
    currentSensors.imu.ax = accel.acceleration.x;
    currentSensors.imu.ay = accel.acceleration.y;
    currentSensors.imu.az = accel.acceleration.z;
    currentSensors.imu.gx = gyro.gyro.x;
    currentSensors.imu.gy = gyro.gyro.y;
    currentSensors.imu.gz = gyro.gyro.z;

    // Calculate acceleration magnitude (m/s²) and gyro magnitude (deg/s)
    float accelMag = sqrt(
        currentSensors.imu.ax * currentSensors.imu.ax +
        currentSensors.imu.ay * currentSensors.imu.ay +
        currentSensors.imu.az * currentSensors.imu.az
    );
    float gyroMagDegPerSec = sqrt(
        currentSensors.imu.gx * currentSensors.imu.gx +
        currentSensors.imu.gy * currentSensors.imu.gy +
        currentSensors.imu.gz * currentSensors.imu.gz
    ) * 57.2958f;

    // Orientation status for phone telemetry.
    // True when cane/IMU is oriented with the configured up-axis direction.
    const float signedZ = currentSensors.imu.az * (float)IMU_UP_AXIS_SIGN;
    orientationFilteredSignedZ =
        orientationFilteredSignedZ * (1.0f - IMU_ORIENTATION_FILTER_ALPHA) +
        signedZ * IMU_ORIENTATION_FILTER_ALPHA;
    imuOrientationOk = (orientationFilteredSignedZ >= IMU_ORIENTATION_Z_THRESHOLD);

    // === FALL DETECTION STATE MACHINE ===
    const unsigned long now = millis();

    switch (fallState) {
        case FALL_STATE_NORMAL:
            if (accelMag < FALL_FREEFALL_THRESHOLD &&
                (now - lastFallTime > FALL_COOLDOWN)) {
                fallState = FALL_STATE_FREE_FALL;
                freeFallStartTime = now;
                if (DEBUG_MODE) {
                    Serial.println("Free fall detected...");
                }
            }
            break;

        case FALL_STATE_FREE_FALL:
            if (now - freeFallStartTime <= FALL_IMPACT_WINDOW) {
                if (accelMag > FALL_IMPACT_THRESHOLD &&
                    gyroMagDegPerSec > FALL_GYRO_THRESHOLD_DPS) {
                    imuFallDetected = true;
                    lastFallTime = now;
                    fallState = FALL_STATE_NORMAL;

                    if (DEBUG_MODE) {
                        Serial.println("========== FALL DETECTED ==========");
                        Serial.print("Impact Accel: ");
                        Serial.print(accelMag, 2);
                        Serial.print(" m/s^2 | Gyro: ");
                        Serial.print(gyroMagDegPerSec, 1);
                        Serial.println(" deg/s");
                    }
                }
            } else {
                fallState = FALL_STATE_NORMAL;
            }
            break;
    }

    // Hold fall flag long enough for fusion/response path to consume reliably.
    if (imuFallDetected && (now - lastFallTime > FALL_INACTIVITY_TIMEOUT)) {
        imuFallDetected = false;
    }

    if (DEBUG_MODE) {
        static unsigned long lastImuDebug = 0;
        if (now - lastImuDebug > 500) {
            lastImuDebug = now;
            Serial.print("IMU Accel=");
            Serial.print(accelMag, 2);
            Serial.print(" m/s^2 Gyro=");
            Serial.print(gyroMagDegPerSec, 1);
            Serial.print(" dps Orient=");
            Serial.println(imuOrientationOk ? "OK" : "FLIPPED");
        }
    }

    // Mark sensor as working
    systemFaults.imu_fail = false;
}