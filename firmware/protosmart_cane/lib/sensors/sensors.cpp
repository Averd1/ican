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
#if !ISOLATED_SENSOR_TEST_MODE
    pulseInit();
#endif
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
#if !ISOLATED_SENSOR_TEST_MODE
    pulseUpdate();
#endif
}