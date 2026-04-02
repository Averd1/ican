#include "mux.h"
#include <Wire.h>

#define MUX_ADDR 0x70

void muxInit() {
    Wire.begin();
}

void selectMux(uint8_t channel) {
    Wire.beginTransmission(MUX_ADDR);
    Wire.write(1 << channel);
    Wire.endTransmission();
}
