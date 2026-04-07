#pragma once

enum Mode {
    NORMAL,
    LOW_POWER,
    EMERGENCY
};

struct ModeConfig {
    int imuInterval;        // IMU sampling interval (ms)
    int ultrasonicInterval; // Ultrasonic sampling interval (ms)
    int lidarInterval;      // LiDAR sampling interval (ms)
    int pulseInterval;      // Pulse sensor sampling interval (ms)
    int batteryCheckInterval; // Battery check interval (ms)
};

extern Mode currentMode;
extern ModeConfig config;
extern int batteryLevel; // Battery percentage (0-100)

void setMode(Mode m);
int getBatteryLevel();
