/*
 * I2C Multiplexer (PCA9548A) Control Header
 */

#pragma once

#include <Arduino.h>
#include "../include/config.h"

void muxInit();
void selectMuxChannel(uint8_t channel);
void selectLidar();
void selectUltrasonic();
void selectIMU();
void selectLight();
void selectHaptic();