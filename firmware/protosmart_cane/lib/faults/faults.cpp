/*
 * Fault Detection and Recovery System
 * Monitors sensor health and implements recovery strategies
 */

#include "faults.h"

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

    // LiDAR fault detection
    static uint8_t lidarFailCount = 0;
    if (currentSensors.lidarDistance == SENSOR_ERROR_DISTANCE) {
        lidarFailCount++;
    } else {
        lidarFailCount = 0;
    }
    systemFaults.lidar_fail = (lidarFailCount >= SENSOR_FAIL_THRESHOLD);

    // Heart sensor fault detection - check for valid BPM readings
    static uint8_t heartFailCount = 0;
    static unsigned long lastHeartBeat = 0;

    if (currentSensors.pulseDetected) {
        lastHeartBeat = millis();
        heartFailCount = 0;
    } else if (millis() - lastHeartBeat > 10000) {  // No beat for 10 seconds
        heartFailCount++;
    }

    systemFaults.heart_fail = (heartFailCount >= SENSOR_FAIL_THRESHOLD);

    // Attempt recovery for failed sensors
    if ((systemFaults.imu_fail || systemFaults.ultrasonic_fail ||
         systemFaults.lidar_fail || systemFaults.heart_fail) &&
        (millis() - systemFaults.lastRecoveryAttempt > SENSOR_RECOVERY_TIME_MS)) {

        if (DEBUG_MODE) Serial.println("Attempting sensor recovery...");

        // Reinitialize failed sensors
        if (systemFaults.imu_fail) imuInit();
        if (systemFaults.ultrasonic_fail) ultrasonicInit();
        if (systemFaults.lidar_fail) lidarInit();
        if (systemFaults.heart_fail) pulseInit();

        systemFaults.lastRecoveryAttempt = millis();
    }
}