/*
 * I2C Multiplexer (PCA9548A) Control
 * Manages channel selection for multiple I2C sensors
 */

#include "mux.h"
#include <Wire.h>

void muxInit() {
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);   // Primary I2C on SDA/A4 and SCL/A5
    Wire1.begin(I2C2_SDA_PIN, I2C2_SCL_PIN); // Secondary I2C on D6 / D7
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
    // LiDAR is on the dedicated secondary I2C bus (Wire1), no primary mux selection required
}

void selectUltrasonic() {
    // Ultrasonic sensors are wired to direct GPIO pins, no I2C mux selection required
}

void selectIMU() {
    // IMU is on the dedicated secondary I2C bus (Wire1), no primary mux selection required
}

void selectLight() {
    selectMuxChannel(LIGHT_CHANNEL);
}

void selectHaptic() {
    selectMuxChannel(HAPTIC_CHANNEL);
}