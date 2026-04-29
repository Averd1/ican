/*
 * Unified Sensor Interface
 * Manages all sensor initialization and updates
 */

#include "sensors.h"
#include "imu.h"
#include "ultrasonic.h"
#include "8x8_sensor.h"
#include "pulse.h"

void sensorsInit() {
    imuInit();
    ultrasonicInit();
    matrixSensorInit();
    pulseInit();
}

void updateIMU() {
    imuUpdate();
}

void updateUltrasonic() {
    ultrasonicUpdate();
}

void updateMatrixSensor() {
    matrixSensorUpdate();
}

void updatePulse() {
    pulseUpdate();
}