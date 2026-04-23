/*
 * Haptic Driver Control (DRV2605L)
 * 3 independent DRV2605 drivers with mux channel selection
 * Intensity and frequency scale with obstacle proximity
 */

#pragma once

#include <Arduino.h>
#include "../include/config.h"
#include "../include/state.h"
#include "../mux/mux.h"

// DRV2605L I2C address
#define DRV2605_ADDR 0x5A

// Haptic driver indices
enum HapticDriverIndex {
    DRIVER_8X8 = 0,
    DRIVER_RIGHT_ULTRASONIC = 1,
    DRIVER_LEFT_ULTRASONIC = 2
};

// Haptic effect intensity levels
#define HAPTIC_OFF 0
#define HAPTIC_LIGHT 50
#define HAPTIC_MEDIUM 150
#define HAPTIC_STRONG 255

void hapticDriverInit();
void updateHapticFeedback();
void hapticPulse(uint8_t driverIndex, uint8_t intensity, uint16_t durationMs);
void hapticStop(uint8_t driverIndex);
uint8_t hapticDriverStatusBits();

extern uint8_t hapticIntensity;
extern unsigned long lastHapticPulse;
extern uint16_t hapticPulseInterval;