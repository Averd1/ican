/*
 * Ambient Light Sensor
 * Detects environmental brightness and triggers LED illumination
 */

#pragma once

void lightSensorInit();
void lightSensorUpdate();

extern uint16_t ambientLux;       // Current ambient light level (lux)
extern bool lowLightDetected;     // True if below threshold