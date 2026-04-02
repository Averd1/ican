#include "imu.h"
#include "imu.h"
#include "mux.h"
#include <Wire.h>
#include <Adafruit_LSM6DSOX.h>

#define IMU_CHANNEL 0

Adafruit_LSM6DSOX lsm6dsox;
IMUData imu;

void initIMU() {
    selectMux(IMU_CHANNEL);

    if (!lsm6dsox.begin_I2C()) {
        Serial.println("IMU NOT FOUND");
        while (1);
    }

    Serial.println("IMU READY");
}

void updateIMU() {
    selectMux(IMU_CHANNEL);

    sensors_event_t accel, gyro, temp;
    lsm6dsox.getEvent(&accel, &gyro, &temp);

    imu.ax = accel.acceleration.x;
    imu.ay = accel.acceleration.y;
    imu.az = accel.acceleration.z;

    imu.gx = gyro.gyro.x;
    imu.gy = gyro.gyro.y;
    imu.gz = gyro.gyro.z;
}
