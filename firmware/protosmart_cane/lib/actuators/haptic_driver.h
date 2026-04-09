/*
 * Haptic Driver Control (DRV2605L)
 * Distance-based haptic feedback scaling
 * Intensity and frequency scale with obstacle proximity
 */

#pragma once

#include "../include/config.h"

// DRV2605L I2C address
#define DRV2605_ADDR 0x5A

// Haptic effect intensity levels
#define HAPTIC_OFF 0
#define HAPTIC_LIGHT 50
#define HAPTIC_MEDIUM 150
#define HAPTIC_STRONG 255

void hapticDriverInit();
void updateHapticFeedback();
void hapticPulse(uint8_t intensity, uint16_t durationMs);
void hapticStop();

extern uint8_t hapticIntensity;
extern bool hapticActive;