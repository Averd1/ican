/*
 * I2C Multiplexer (PCA9548A) Control Header
 */

#pragma once

#include <Arduino.h>
#include "../include/config.h"

bool muxInit();
bool selectMuxChannel(uint8_t channel);
void selectLidar();
void selectUltrasonic();
void selectIMU();
void selectLight();

// === HAPTIC DRIVER CHANNEL SELECTION ===
void selectHapticHead();
void selectHapticLeft();
void selectHapticRight();
