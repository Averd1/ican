/*
 * Sensor Fusion Module
 * Combines data from all sensors to determine current situation
 */

#include "fusion.h"

void fuseSituations() {
    // PRIORITY 1: IMU fall detection overrides all other situation fusion.
    if (imuFallDetected) {
        currentSituation = FALL_DETECTED;
        return;
    }

    // Get minimum distance from all sensors
    uint16_t minDistance = 0xFFFF;  // Start with max value

    // Check ultrasonic sensors
    for (uint8_t i = 0; i < NUM_ULTRASONIC_SENSORS; i++) {
        if (currentSensors.ultrasonicDistances[i] != SENSOR_ERROR_DISTANCE &&
            currentSensors.ultrasonicDistances[i] < minDistance) {
            minDistance = currentSensors.ultrasonicDistances[i];
        }
    }

    // Check matrix sensor
    if (currentSensors.matrixSensorDistance != SENSOR_ERROR_DISTANCE &&
        currentSensors.matrixSensorDistance < minDistance) {
        minDistance = currentSensors.matrixSensorDistance;
    }

    // PRIORITY 2: HIGH STRESS CONDITION
    // Close obstacle + abnormal heart rate
    if (minDistance <= OBSTACLE_IMMINENT_MM && currentSensors.heartAbnormal) {
        currentSituation = HIGH_STRESS_EVENT;
        return;
    }

    // PRIORITY 3: OBSTACLE DETECTION HIERARCHY
    if (minDistance <= OBSTACLE_IMMINENT_MM) {
        currentSituation = OBJECT_IMMINENT;
    } else if (minDistance <= OBSTACLE_NEAR_MM) {
        currentSituation = OBJECT_NEAR;
    } else if (minDistance <= 1000) {  // Far obstacle threshold
        currentSituation = OBJECT_FAR;
    } else {
        currentSituation = NONE;
    }
}