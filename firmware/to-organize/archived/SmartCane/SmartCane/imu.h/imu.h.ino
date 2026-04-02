#pragma once

struct IMUData {
    float ax, ay, az;
    float gx, gy, gz;
};

extern IMUData imu;

void initIMU();
void updateIMU();
