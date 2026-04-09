#pragma once

#include <Arduino.h>
#include "../../mux/mux.h"

// TF Luna LiDAR I2C addresses and registers
#define LIDAR_I2C_ADDR 0x10
#define LIDAR_DIST_LOW 0x01
#define LIDAR_DIST_HIGH 0x02
#define LIDAR_TRIGGER 0x04

// Zone detection thresholds (mm)
#define OBSTACLE_NEAR 500
#define OBSTACLE_IMMINENT 200

// Zone detection results
extern bool obstacleNear;
extern bool obstacleImminent;
extern uint16_t lidarDistance;

void initLidar();
void updateLidarData();
uint16_t readLidarDistance();