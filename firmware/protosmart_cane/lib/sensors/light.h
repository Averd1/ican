/*
 * Ambient Light Sensor
 * Detects environmental brightness and triggers LED illumination
 */

#pragma once

#include <Arduino.h>
#include "../include/config.h"
#include "../mux/mux.h"

void lightSensorInit();
void lightSensorUpdate();

extern uint16_t ambientLux;       // Current ambient light level (lux)
extern bool lowLightDetected;     // True if below threshold