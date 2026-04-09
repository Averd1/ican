/*
 * LiDAR Sensor (TF Luna) Implementation
 * Handles forward obstacle detection
 */

#include "lidar.h"
#include <Wire.h>

void lidarInit() {
    selectLidar();

    // Test communication
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    if (Wire.endTransmission() != 0) {
        if (DEBUG_MODE) Serial.println("LiDAR sensor initialization failed!");
        systemFaults.lidar_fail = true;
        return;
    }

    if (DEBUG_MODE) Serial.println("LiDAR sensor initialized successfully");
    systemFaults.lidar_fail = false;
}

void lidarUpdate() {
    selectLidar();

    currentSensors.lidarDistance = readLidarDistance();

    // Update zone detection flags
    if (currentSensors.lidarDistance != SENSOR_ERROR_DISTANCE) {
        if (currentSensors.lidarDistance <= OBSTACLE_IMMINENT_MM) {
            obstacleImminent = true;
            obstacleNear = true;
        } else if (currentSensors.lidarDistance <= OBSTACLE_NEAR_MM) {
            obstacleImminent = false;
            obstacleNear = true;
        } else {
            obstacleImminent = false;
            obstacleNear = false;
        }
        systemFaults.lidar_fail = false;
    } else {
        obstacleImminent = false;
        obstacleNear = false;
        systemFaults.lidar_fail = true;
    }
}

uint16_t readLidarDistance() {
    // Trigger measurement
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    Wire.write(0x04);  // Trigger register
    Wire.write(0x01);  // Start measurement
    if (Wire.endTransmission() != 0) {
        return SENSOR_ERROR_DISTANCE;
    }

    // Wait for measurement (TF Luna needs ~10ms)
    delay(10);

    // Read distance registers
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    Wire.write(0x01);  // Distance low byte register
    if (Wire.endTransmission() != 0) {
        return SENSOR_ERROR_DISTANCE;
    }

    Wire.requestFrom(LIDAR_I2C_ADDR, 2);
    if (Wire.available() >= 2) {
        uint8_t low = Wire.read();
        uint8_t high = Wire.read();
        uint16_t distance = (high << 8) | low;

        // Validate reading (TF Luna returns 0 for invalid readings)
        if (distance == 0) {
            return SENSOR_ERROR_DISTANCE;
        }

        return distance;
    }

    return SENSOR_ERROR_DISTANCE;
}