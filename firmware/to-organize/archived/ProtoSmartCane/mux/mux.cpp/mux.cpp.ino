#include "mux.h"
#include <Wire.h>

void muxInit() {
    Wire.begin();
    // Disable all channels initially
    Wire.beginTransmission(MUX_ADDR);
    Wire.write(0x00);
    Wire.endTransmission();
}

void selectMuxChannel(uint8_t channel) {
    if (channel > 7) return; // PCA9548A has 8 channels (0-7)

    Wire.beginTransmission(MUX_ADDR);
    Wire.write(1 << channel);
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
