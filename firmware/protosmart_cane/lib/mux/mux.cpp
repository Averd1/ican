/*
 * I2C Multiplexer (PCA9548A) Control
 * Manages channel selection for multiple I2C sensors
 */

#include "mux.h"
#include <Wire.h>

void muxInit() {
    Wire.begin();
    // Disable all channels initially for safety
    selectMuxChannel(0xFF);  // 0xFF disables all channels
}

void selectMuxChannel(uint8_t channel) {
    if (channel > 7 && channel != 0xFF) return; // Valid channels 0-7, 0xFF to disable all

    Wire.beginTransmission(MUX_ADDR);
    if (channel == 0xFF) {
        Wire.write(0x00);  // Disable all channels
    } else {
        Wire.write(1 << channel);  // Enable specific channel
    }
    Wire.endTransmission();
}

void selectLidar() {
    selectMuxChannel(LIDAR_CHANNEL);
}

void selectUltrasonic() {
    selectMuxChannel(ULTRASONIC_CHANNEL);
}

void selectIMU() {
    selectMuxChannel(IMU_CHANNEL);
}

void selectLight() {
    selectMuxChannel(LIGHT_CHANNEL);
}

void selectHaptic() {
    selectMuxChannel(HAPTIC_CHANNEL);
}