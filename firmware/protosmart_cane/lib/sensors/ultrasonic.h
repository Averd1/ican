/*
 * Ultrasonic Sensor Header
 */

#pragma once

#include "../include/config.h"
#include "../include/state.h"
#include "../mux/mux.h"

void ultrasonicInit();
void ultrasonicUpdate();
uint16_t readUltrasonicDistance(uint8_t sensorIndex);