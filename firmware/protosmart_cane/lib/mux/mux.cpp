/*
 * I2C Multiplexer (PCA9548A) Control
 * Manages channel selection for multiple I2C sensors
 */

#include "mux.h"
#include <Wire.h>
#include "../include/state.h"

bool muxInit() {
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);     // Primary I2C: GPIO11(SDA) / GPIO12(SCL)
    Wire1.begin(I2C2_SDA_PIN, I2C2_SCL_PIN);  // Secondary I2C: GPIO9(SDA) / GPIO10(SCL) — IMU + 8x8

    Wire.beginTransmission(MUX_ADDR);
    if (Wire.endTransmission() != 0) {
        systemFaults.mux_fail = true;
        if (DEBUG_MODE) Serial.println("I2C mux not found at configured address");
        return false;
    }

    // Disable all channels initially for safety
    bool disabled = selectMuxChannel(0xFF);  // 0xFF disables all channels
    systemFaults.mux_fail = !disabled;
    return disabled;
}

bool selectMuxChannel(uint8_t channel) {
    if (channel > 7 && channel != 0xFF) return false; // Valid channels 0-7, 0xFF to disable all

    Wire.beginTransmission(MUX_ADDR);
    if (channel == 0xFF) {
        Wire.write(0x00);  // Disable all channels
    } else {
        Wire.write(1 << channel);  // Enable specific channel
    }
    bool ok = (Wire.endTransmission() == 0);
    systemFaults.mux_fail = !ok;
    return ok;
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

// === HAPTIC DRIVER CHANNEL SELECTION ===
void selectHapticHead() {
    selectMuxChannel(HAPTIC_HEAD_CHANNEL);
}

void selectHapticLeft() {
    selectMuxChannel(HAPTIC_LEFT_CHANNEL);
}

void selectHapticRight() {
    selectMuxChannel(HAPTIC_RIGHT_CHANNEL);
}
