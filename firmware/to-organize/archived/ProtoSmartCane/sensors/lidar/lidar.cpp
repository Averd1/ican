#include "lidar.h"
#include "../../mux/mux.h"
#include <Wire.h>

bool obstacleNear = false;
bool obstacleImminent = false;
uint16_t lidarDistance = 0;

void initLidar() {
    selectLidar();

    // Test communication with TF Luna
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    if (Wire.endTransmission() == 0) {
        Serial.println("TF Luna LiDAR initialized");
    } else {
        Serial.println("TF Luna LiDAR initialization failed");
    }
}

void updateLidarData() {
    selectLidar();
    lidarDistance = readLidarDistance();

    // Update zone detection based on distance
    if (lidarDistance > 0 && lidarDistance <= OBSTACLE_IMMINENT) {
        obstacleImminent = true;
        obstacleNear = true;
    } else if (lidarDistance > 0 && lidarDistance <= OBSTACLE_NEAR) {
        obstacleImminent = false;
        obstacleNear = true;
    } else {
        obstacleImminent = false;
        obstacleNear = false;
    }
}

uint16_t readLidarDistance() {
    // Trigger measurement
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    Wire.write(LIDAR_TRIGGER);
    Wire.write(0x01); // Trigger measurement
    if (Wire.endTransmission() != 0) {
        return 0; // Error
    }

    delay(10); // Wait for measurement (TF Luna response time ~10ms)

    // Read distance registers
    Wire.beginTransmission(LIDAR_I2C_ADDR);
    Wire.write(LIDAR_DIST_LOW);
    if (Wire.endTransmission() != 0) {
        return 0; // Error
    }

    Wire.requestFrom(LIDAR_I2C_ADDR, 2);
    if (Wire.available() >= 2) {
        uint8_t low = Wire.read();
        uint8_t high = Wire.read();
        return (high << 8) | low;
    }

    return 0; // No data available
}