#pragma once

#include <Arduino.h>

// I2C Multiplexer (PCA9548A) address
#define MUX_ADDR 0x70

// Sensor I2C addresses
#define LIDAR_I2C_ADDR 0x10      // TF Luna LiDAR
#define ULTRASONIC_I2C_ADDR 0x11 // URM37 Ultrasonic
#define IMU_I2C_ADDR 0x6A        // LSM6DSOX IMU (primary)

// Mux channel assignments (adjust based on hardware wiring)
#define LIDAR_CHANNEL 0
#define ULTRASONIC_CHANNEL 1
#define IMU_CHANNEL 2

void muxInit();
void selectMuxChannel(uint8_t channel);
void selectLidar();
void selectUltrasonic();
void selectIMU();
#include <Arduino.h>

void muxInit();
void selectMux(uint8_t channel);
