/*
 * Fault Detection and Recovery System
 * Monitors sensor health and implements recovery strategies
 */

#include "faults.h"
#include "../sensors/imu.h"
#include "../sensors/ultrasonic.h"
#include "../sensors/8x8_sensor.h"
#include "../sensors/pulse.h"

void checkFaults() {
    // IMU fault detection - check for valid readings
    static uint8_t imuFailCount = 0;
    if (isnan(currentSensors.imu.ax) || isnan(currentSensors.imu.ay) || isnan(currentSensors.imu.az)) {
        imuFailCount++;
    } else {
        imuFailCount = 0;
    }
    systemFaults.imu_fail = (imuFailCount >= SENSOR_FAIL_THRESHOLD);

    // Ultrasonic fault detection - check for valid distance readings
    static uint8_t ultrasonicFailCount = 0;
    bool ultrasonicValid = false;
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        if (currentSensors.ultrasonicDistances[i] != SENSOR_ERROR_DISTANCE) {
            ultrasonicValid = true;
            break;
        }
    }
    if (!ultrasonicValid) {
        ultrasonicFailCount++;
    } else {
        ultrasonicFailCount = 0;
    }
    systemFaults.ultrasonic_fail = (ultrasonicFailCount >= SENSOR_FAIL_THRESHOLD);

    // Matrix sensor fault detection
    static uint8_t matrixSensorFailCount = 0;
    if (currentSensors.matrixSensorDistance == SENSOR_ERROR_DISTANCE) {
        matrixSensorFailCount++;
    } else {
        matrixSensorFailCount = 0;
    }
    systemFaults.matrixSensor_fail = (matrixSensorFailCount >= SENSOR_FAIL_THRESHOLD);

    // Heart sensor auto-recovery disabled for now.
    // During normal use the pulse signal can legitimately be absent/noisy,
    // which would otherwise cause continuous fault-recovery loops.
    systemFaults.heart_fail = false;

    // Attempt recovery for failed sensors
    if ((systemFaults.imu_fail || systemFaults.ultrasonic_fail ||
         systemFaults.matrixSensor_fail || systemFaults.heart_fail) &&
        (millis() - systemFaults.lastRecoveryAttempt > SENSOR_RECOVERY_TIME_MS)) {

        if (DEBUG_MODE) Serial.println("Attempting sensor recovery...");

        // Reinitialize failed sensors
        if (systemFaults.imu_fail) imuInit();
        if (systemFaults.ultrasonic_fail) ultrasonicInit();
        if (systemFaults.matrixSensor_fail) matrixSensorInit();
        if (systemFaults.heart_fail) pulseInit();

        systemFaults.lastRecoveryAttempt = millis();
    }
}