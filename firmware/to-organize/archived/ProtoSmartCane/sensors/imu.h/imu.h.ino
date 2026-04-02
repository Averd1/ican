#pragma once

struct IMUData {
    float ax, ay, az;
    float gx, gy, gz;
};

extern IMUData imu;

extern bool imuFallCandidate;
extern bool imuInactive;

void initIMU();
void updateIMU();
