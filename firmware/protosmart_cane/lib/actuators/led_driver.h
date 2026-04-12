/*
 * LED Driver Control - High-Power LED Illumination
 * Controls bright LED for low-light navigation
 */

#pragma once

#include <Arduino.h>
#include "../include/config.h"
#include "../include/state.h"
#include "../sensors/light.h"

void ledDriverInit();
void updateLEDIllumination();
void setLEDIlluminationBrightness(uint8_t brightness);
void setBoostConverterEnabled(bool enabled);

extern uint8_t ledBrightness;      // Current LED brightness (0-255)
extern bool ledEnabled;            // LED currently on