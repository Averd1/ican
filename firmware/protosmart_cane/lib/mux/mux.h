/*
 * I2C Multiplexer (PCA9548A) Control Header
 */

#pragma once

#include "../include/config.h"

void muxInit();
void selectMuxChannel(uint8_t channel);
void selectLidar();
void selectUltrasonic();
void selectIMU();