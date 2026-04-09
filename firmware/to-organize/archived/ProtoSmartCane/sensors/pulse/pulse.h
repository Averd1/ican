#pragma once

#include <Arduino.h>

// Pulse sensor configuration - consolidated from heart sensor
#define PULSE_PIN A0
#define PULSE_LED LED_BUILTIN
#define PULSE_THRESHOLD 2000  // LOWER this for ESP32

// Heart rate monitoring variables
extern int heartBPM;
extern int heartRaw;
extern bool pulseDetected;
extern bool heartAbnormal;

void initPulse();
void updatePulseData();