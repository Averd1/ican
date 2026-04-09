/*
 * LED Driver Control - High-Power LED Illumination
 * Controls bright LED for low-light navigation
 */

#pragma once

#include "../include/config.h"

void ledDriverInit();
void updateLEDIllumination();
void setLEDIlluminationBrightness(uint8_t brightness);

extern uint8_t ledBrightness;      // Current LED brightness (0-255)
extern bool ledEnabled;            // LED currently on