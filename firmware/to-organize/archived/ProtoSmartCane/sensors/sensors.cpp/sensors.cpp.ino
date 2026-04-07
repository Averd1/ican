#include "sensors.h"
#include "../imu/imu.h"
#include "../ultrasonic/ultrasonic.h"
#include "../lidar/lidar.h"
#include "../pulse/pulse.h"
#include <Arduino.h>

// ---- FALL STATE ----
bool fallDetected = false;

// cooldown to prevent spam
static unsigned long lastFallTime = 0;
static const unsigned long FALL_COOLDOWN = 5000; // 5 sec

void initSensors() {
    initIMU();
    initUltrasonic();
    initLidar();
    initPulse();
}

void updateIMU() {
    // IMU update logic handled in imu.cpp
    updateIMUData();
}

void updateUltrasonic() {
    // Ultrasonic update logic handled in ultrasonic.cpp
    updateUltrasonicData();
}

void updateLidar() {
    // LiDAR update logic handled in lidar.cpp
    updateLidarData();
}

void updatePulse() {
    // Pulse sensor update logic handled in pulse.cpp
    updatePulseData();
}
