/*
 * Unified Sensor Interface
 * Manages all sensor initialization and updates
 */

#include "sensors.h"
#include "imu.h"
#include "ultrasonic.h"
#include "lidar.h"
#include "pulse.h"

void sensorsInit() {
    imuInit();
    ultrasonicInit();
    lidarInit();
    pulseInit();
}

void updateIMU() {
    imuUpdate();
}

void updateUltrasonic() {
    ultrasonicUpdate();
}

void updateLidar() {
    lidarUpdate();
}

void updatePulse() {
    pulseUpdate();
}