#pragma once

struct SensorData {
    int dist_left;
    int dist_right;
    float lux;
    int heart_raw;
};

extern SensorData sensor;

void initSensors();
void updateSensors();
