#include "light.h"
#include "../mux/mux.h"
#include <Adafruit_VEML7700.h>

#define LIGHT_CHANNEL 1

Adafruit_VEML7700 veml;
float lux = 0;

void initLight() {
    selectMux(LIGHT_CHANNEL);
    veml.begin();
}

void updateLight() {
    selectMux(LIGHT_CHANNEL);
    lux = veml.readLux();
}
